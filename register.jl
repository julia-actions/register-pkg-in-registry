using Pkg: GitTools
using GitHub: GitHub
using Registrator: Registrator
using RegistryTools: RegistryTools
using URIs: URI
using LibGit2: LibGit2

# ARGS
# 1. subdirectory
# 2. inputs.registry
# 3. inputs.name
# 4. inputs.email
# 5. inputs.push
# 6. github.actor
subdirectory, registry, name, email, push, actor = ARGS
push = parse(Bool, push)

pkg_local_repo_path = pwd()
pkg_local_repo = LibGit2.GitRepo(pkg_local_repo_path)
pkg_url = LibGit2.url(LibGit2.get(LibGit2.GitRemote, pkg_local_repo, "origin"))
# Always append `.git` to the URL of the package
if !endswith(pkg_url, ".git")
    pkg_url *= ".git"
end
@info "Repository = $pkg_url"

project_path = joinpath(subdirectory, "Project.toml")
project = RegistryTools.Project(project_path)
isnothing(project) && error("Project file not found")
@info "Project" project_path project.name project.uuid project.version

commit_hash = LibGit2.head(pkg_local_repo_path)
tree_hash = bytes2hex(GitTools.tree_hash(pkg_local_repo_path))
@info "Hash" commit_hash tree_hash

const private_reg_url = "https://github.com/$(registry).git"
# The "username" must be specified (any name would work here), see
# <https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation#about-authentication-as-a-github-app-installation>.
const private_reg_uri = string(URI(private_reg_url; userinfo="""$(name):$(ENV["GITHUB_TOKEN"])"""))
const general_reg_url = "https://github.com/JuliaRegistries/General"

registry_repo = RegistryTools.get_registry(private_reg_uri; force_reset=false)

const branch = get(ENV, "INPUTS_BRANCH", RegistryTools.registration_branch(project; url=pkg_url))

@info "Registry" private_reg_url registry_repo branch

pr = cd(mktempdir()) do
    # adapted from fregante/setup-git-user@v1, https://stackoverflow.com/a/71984173
    regbranch = RegistryTools.register(
        pkg_url, project, tree_hash;
        registry=private_reg_uri,
        registry_deps=[general_reg_url],
        push=push,
        branch=branch,
        gitconfig=Dict(
            "user.name" => name,
            "user.email" => email,
            "url.$(private_reg_uri).insteadOf" => private_reg_url,
        ),
    )
    @info "RegBranch = $(regbranch)"

    if haskey(regbranch.metadata, "error")
        if regbranch.metadata["kind"] == "New version" && regbranch.metadata["error"] == "Version $(project.version) already exists"
            println("::warning file=Project.toml,line=3,col=11,endColumn=$(11 + 1 + length(string(project.version))),title=Package not registered::Version $(project.version) already exists")
            return 0
        else
            println("::error file=Project.toml,title=$(regbranch.metadata["kind"])::$(regbranch.metadata["error"])")
            error(regbranch.metadata["error"])
        end
    end

    # open pull request
    params = Dict(
        "base" => "main",
        "head" => branch,
        "maintainer_can_modify" => true,
    )

    params["title"], params["body"] = Registrator.pull_request_contents(
        registration_type=get(regbranch.metadata, "kind", ""),
        package=project.name,
        repo=pkg_url,
        user="@$actor",
        version=project.version,
        commit=commit_hash,
        release_notes="",
    )
    @info "Pull Request contents" params["title"] params["body"]

    auth = GitHub.authenticate(ENV["GITHUB_TOKEN"])
    try
        pr = GitHub.create_pull_request(registry; auth, params)
        GitHub.add_labels(registry, pr, lowercase.(regbranch.metadata["labels"]); auth)
        pr
    catch err
        if err isa ErrorException && contains(err.msg, "A pull request already exists for")
            @info "A pull request already exists"

            prs = GitHub.pull_requests(registry; auth)[1]
            filter!(pr -> pr.state == "open" && pr.head.ref == branch, prs)
            if length(prs) == 1
                pr = only(prs)

                # "head" is not documented to be accepted as parameter:
                # <https://docs.github.com/en/rest/pulls/pulls?apiVersion=2026-03-10#update-a-pull-request>.
                delete!(params, "head")
                # Somehow the presence of "maintainer_can_modify" causes the error
                # "Fork collab can only be enabled on cross-repo pull requests".
                delete!(params, "maintainer_can_modify")
                GitHub.update_pull_request(registry, pr; auth, params)
                pr
            else
                error("Expected to find one open pull request created from a previous registration attempt but got $(length(prs)) pull requests")
            end
        else
            rethrow()
        end
    end
end

open(ENV["GITHUB_OUTPUT"], "w") do io
    println(io, "name=$(project.name)")
    println(io, "uuid=$(project.uuid)")
    println(io, "version=$(project.version)")
    println(io, "hash=$tree_hash")
    println(io, "branch=$branch")
    println(io, "path=$(LibGit2.path(registry_repo))")
end

open(ENV["GITHUB_STEP_SUMMARY"], "w") do io
    println(
        io,
        """
        # Package registered :package:

        - Registry: $(private_reg_url)
        - Project: $(project.name)
        - UUID: $(project.uuid)
        - Version: $(project.version)
        - Pull Request: $(pr.html_url.uri)
        """
    )
end
