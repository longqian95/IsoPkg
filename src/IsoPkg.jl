module IsoPkg

using Pkg
using TOML
using UUIDs

export @iso

const DEFAULT_GROUP=string("v",VERSION.major,".",VERSION.minor)

"""Name of the current package group"""
const GROUP=Ref(DEFAULT_GROUP)

function env_path()
    depots=Pkg.depots1()
    pos="env_isolated_packages"
    p=joinpath(Pkg.depots1(),pos,GROUP[])
    isdir(p) || mkpath(p)
    return p
end

"""
    switch_group(group_name::String)
    switch_group()

Switch the current package group to `group_name`. If not given, switch to the default group name, which is just current Julia version string such as "v1.2". Switching to a new group name will create the group.
"""
function switch_group(group_name::String=DEFAULT_GROUP)
    if group_name=="" || occursin(r"^\.*$|[/\\]",group_name)
        error("\"$group_name\" is invalid name")
    else 
        GROUP[]=group_name
    end
    return nothing
end

"""
    list_group(;detail=false)

List all available package groups with "group_name (number_of_packages)" form. If `detail` is true, also list the packages in each group.
"""
function list_group(;detail=false)
    ep=dirname(env_path())
    cur_group=GROUP[]
    groups=filter(!=(cur_group),readdir(ep))

    println("Available groups:")
    for g in groups
        pkgs=readdir(joinpath(ep,g))
        n=length(pkgs)
        if n>0
            print("  ")
            printstyled(g;color=:light_yellow)
            println(" ($n)")
            if detail
                for p in pkgs
                    printstyled("    "*p;color=:light_black)
                    println()
                end
            end
        end
    end

    println()
    println("Current group:")
    pkgs=readdir(joinpath(ep,cur_group))
    n=length(pkgs)
    print("  ")
    printstyled(cur_group;color=:light_yellow)
    println(" ($n)")
    if detail
        for p in pkgs
            printstyled("    "*p;color=:light_black)
            println()
        end
    end
end


# This is adapted over from LocalRegistry.jl
# It does not work if there is only General.tar.gz in registries
function our_collect_registries()
    registries = []
    for depot in Pkg.depots()
        isdir(depot) || continue
        reg_dir = joinpath(depot, "registries")
        isdir(reg_dir) || continue
        for name in readdir(reg_dir)
            file = joinpath(reg_dir, name, "Registry.toml")
            if !isfile(file)
                # Packed registry in Julia 1.7+.
                file = joinpath(reg_dir, "$(name).toml")
            end
            if isfile(file)
                content =TOML.parsefile(file)
                spec = (
                    name = content["name"]::String,
                    uuid = UUID(content["uuid"]::String),
                    url = get(content, "repo", nothing)::Union{String,Nothing},
                    path = file
                )
                push!(registries, spec)
            end
        end
    end
    return registries
end

#Search if pkg exists in the registry
function search_registry(pkg::AbstractString)
    for registry in our_collect_registries()
        data=TOML.parsefile(registry.path)
        for (_uuid, pkgdata) in data["packages"]
            if pkg==pkgdata["name"]
                return true
            end
        end
    end
    return false
end

# #Search if pkg exists in the registry
# function search_registry(pkg::AbstractString)
#     for registry in Pkg.Types.collect_registries()
#         data = Pkg.Types.read_registry(joinpath(registry.path, "Registry.toml"))
#         for (_uuid, pkgdata) in data["packages"]
#             if pkg==pkgdata["name"]
#                 return true
#             end
#         end
#     end
#     return false
# end

function str2spec(pkg::String)
    if '@' in pkg
        name,ver=string.(split(pkg,'@'))
        ver=string(VersionNumber(ver))
        p=Pkg.PackageSpec(name=name,version=ver)
    else
        name,ver=pkg,""
        p=Pkg.PackageSpec(name=pkg)
    end
    return (name=name,ver=ver,spec=p)
end

#Search if `pkg` is installed. If installed, return (pkg, name, ver, path), otherwise raise an error.
function search_pkg(pkg::String)
    name,ver=str2spec(pkg)
    found=String[]
    env=env_path()
    for n in readdir(env)
        if n==pkg
            return (pkg=pkg,name=name,ver=ver,path=joinpath(env,pkg))
        elseif !in('@',pkg) && startswith(n,pkg*"@")
            push!(found,n)
        end
    end
    if length(found)==1
        name,ver=str2spec(found[1])
        return (pkg=found[1],name=name,ver=ver,path=joinpath(env,found[1]))
    elseif length(found)>1
        error("Found multiple packages: $found. Please specify an exact name.")
    else
        #if search_registry(name)
            error("\"$pkg\" is not installed. Use IsoPkg.add(\"$pkg\") to install it.")
        #else
        #    error("\"$name\" is invalid (not found in registry).")
        #end 
    end
end

#Get detailed information about `pkg` according to Project.toml and Manifest.toml
function pkg_info(pkg::AbstractString)
    path=joinpath(env_path(),pkg)
    name=uuid=ver=""
    pinned=false
    deps=String[]

    try
        p=Pkg.TOML.parsefile(joinpath(path,"Project.toml"))
        name,uuid=first(p["deps"])
    catch
    end

    if name!=""
        try
            p=Pkg.TOML.parsefile(joinpath(path,"Manifest.toml"))
            if "deps" in keys(p)
                m=p["deps"][name][1]
            else
                m=p[name][1]
            end
            ver=get(m,"version",ver)
            deps=get(m,"deps",deps)
            pinned=get(m,"pinned",pinned)
        catch
        end
    end
    return (name=name,uuid=uuid,ver=ver,deps=deps,pinned=pinned)
end

function activate(pkg::AbstractString)
    env=env_path()
    if pkg in readdir(env)
        Pkg.activate(joinpath(env,pkg))
    elseif occursin(r"^\.*$|[/\\]",pkg)
        error("\"$pkg\" is invalid name")
    else
        @info "New \"$pkg\""
        Pkg.activate(joinpath(env,pkg))
    end
end

"""
    @iso(using_or_import_statement)
    @iso(using_or_import_statement, version_string)

Load a package or a package with a specified version. Currently, it does not support loading multiple packages at once.

# Examples

    #Load Glob (after `IsoPkg.add("Glob")`)
    @iso using Glob

    #Load UnicodePlots v1.2.0 (after `IsoPkg.add("UnicodePlots@1.2.0")`)
    @iso using UnicodePlots "1.2.0"

-----------------------------------------------

    @iso(pkg_name, statement)

Run `statement` in the `pkg_name` environment.

# Examples

    #Load Glob v1.2.0 (after `IsoPkg.add("Glob@1.2.0")`; equivalent to `@iso using Glob "1.2.0"`
    @iso "Glob@1.2.0" using Glob

    #Test Glob
    @iso "Glob@1.2.0" Pkg.test("Glob")

    #Show Glob status (equivalent to `IsoPkg.status("Glob@1.2.0")`)
    @iso "Glob@1.2.0" pkg"status --manifest"
"""
macro iso(expr1,expr2="")
    if typeof(expr1)==Expr && (expr1.head==:import || expr1.head==:using)
        if length(expr1.args)>1
            @error "@iso currently does not support $(expr1.head) multiple modules"
            return nothing
        elseif expr1.args[1].head==:(.)
            if expr1.args[1].args[1]!=:(.)
                name=string(expr1.args[1].args[1])
            else
                @error "@iso cannot be used with relative-$(expr1.head) qualifiers"
                return nothing
            end
        elseif expr1.args[1].head==:(:)  && expr1.args[1].args[1].head==:(.)
            if expr1.args[1].args[1].args[1]!=:(.)
                name=string(expr1.args[1].args[1].args[1])
            else
                @error "@iso cannot be used with relative-$(expr1.head) qualifiers"
                return nothing
            end
        else
            @error "@iso should not be used with \"$expr1\""
            return nothing
        end
        return quote
            n=$name
            ver=$(esc(expr2))
            pkg = search_pkg(ver=="" ? n : n*"@"*ver).pkg
            @iso pkg $(esc(expr1))
        end
    else
        return quote
            pkg=$(esc(expr1))
            if !(typeof(pkg)<:AbstractString)
                error("@iso should not be used with \"$($(string(expr1)))\"")
            end
            cur_proj=dirname(Pkg.Types.find_project_file())
            try
                activate(pkg)
                $(esc(expr2))
            finally
                Pkg.activate(cur_proj)
            end
        end
    end
end


"""
    add(pkg::AbstractString)

Install a package.

If `pkg` is in the "name@ver" form, then the specified version will be added and pinned.

# Examples

    #install Glob
    IsoPkg.add("Glob")

    #install Glob v1.2.0 and pin the version
    IsoPkg.add("Glob@1.2.0")
"""
function add(pkg::AbstractString)
    name,ver,spec=str2spec(pkg)
    #if search_registry(name)
        if ver==""
            @iso name Pkg.add(spec)
        else
            pkg=name*"@"*ver
            @iso pkg begin
                Pkg.add(spec)
                if !pkg_info(pkg).pinned
                    Pkg.pin(spec)
                end
            end
        end
    #else
    #    @error "\"$name\" not found in registry"
    #end
    return nothing
end

"""
    rm(pkg::AbstractString)

Remove a package.
"""
function rm(pkg::AbstractString)
    Base.rm(search_pkg(pkg).path; recursive=true)
    return nothing
end

"""
    update(;force=false)

Update all packages. The packages which names include version (such as name@ver) will NOT be updated. This will help the scripts which rely on this kind of packages not break.

If really want to update all installed package, set `force` to true. (Be careful)
"""
function update(; force=false)
    for pkg in readdir(env_path())
        if force || !('@' in pkg)
            try
                @iso pkg Pkg.update()
            catch
                @info "Update \"$pkg\" error."
            end
        end
    end
    return nothing
end

"""
    update(pkg::AbstractString)

Upgrade a package. The package which name includes version (such as name@ver) will NOT be updated except `force` is true.
"""
function update(pkg::AbstractString; force=false)
    if force || !('@' in pkg)
        @iso search_pkg(pkg).pkg Pkg.update()
    end
    return nothing
end

"""
    status()

Show the status all installed packages.
"""
function status()
    for pkg in readdir(env_path())
        p=pkg_info(pkg)
        u = p.uuid=="" ? ' '^8 : p.uuid[1:8]
        u = "[$u] "
        v = p.ver=="" ? "" : "v"*p.ver
        pin = p.pinned ? " ⚲" : ""
        printstyled(u;color=:light_black); printstyled(pkg;color=:light_yellow)
        s=""
        if pkg==p.name
            s*=" ($v$pin)"
        elseif pkg!=p.name*"@"*p.ver
            s*=" ($(p.name) - $v$pin)"
        else
            s*=pin
        end
        println(s)
    end
    return nothing
end

"""
    status(pkg::AbstractString)

Show the status of a package.
"""
function status(pkg::AbstractString)
    @iso search_pkg(pkg).pkg Pkg.status(mode=PKGMODE_MANIFEST)
    return nothing
end

"""
    pin(pkg::AbstractString)

Pin the package version and change its name to match version if possible.
"""
function pin(pkg::AbstractString)
    env=env_path()
    pkgs=readdir(env)
    pkg,name,ver,path=search_pkg(pkg)
    p=pkg_info(pkg)
    newpkg=p.name*"@"*p.ver
    if p.ver!=""
        if p.name==name && p.ver!=ver && !(newpkg in pkgs)
            p.pinned || @iso pkg Pkg.pin(p.name)
            mv(path,joinpath(env,newpkg))
        else
            if p.pinned
                println("\"$pkg\" is already pinned")
            else
                @iso pkg Pkg.pin(p.name)
            end
        end
    else
        error("Cannot get the version of \"$pkg\"")
    end
    return nothing
end

"""
    free(pkg::AbstractString)

Free the package version and remove the version in name if possible.
"""
function free(pkg::AbstractString)
    env=env_path()
    pkgs=readdir(env)
    pkg,name,ver,path=search_pkg(pkg)
    p=pkg_info(pkg)
    newpkg=p.name
    if p.ver!=""
        if p.name==name && ver!="" && !(newpkg in pkgs)
            p.pinned && @iso pkg Pkg.free(p.name)
            mv(path,joinpath(env,newpkg))
        else
            if p.pinned
                @iso pkg Pkg.free(p.name)
            else
                println("\"$pkg\" is already freed")
            end
        end
    else
        error("Cannot get the version of \"$pkg\"")
    end
    return nothing
end

"""
    show_not_newest_pkgs()

Return the packages which is not the newest version in current environment.

Ref: https://www.juliabloggers.com/understanding-package-version-restrictions-in-julia
"""
function show_not_newest_pkgs()
    cd(joinpath(DEPOT_PATH[1], "registries", "General")) do
       deps = Pkg.dependencies()
       registry = Pkg.TOML.parse(read("Registry.toml", String))
       general_pkgs = registry["packages"]

       constrained = Dict{String, Tuple{VersionNumber,VersionNumber}}()
       for (uuid, dep) in deps
           suuid = string(uuid)
           dep.is_direct_dep || continue
           dep.version === nothing && continue
           haskey(general_pkgs, suuid) || continue
           pkg_meta = general_pkgs[suuid]
           pkg_path = joinpath(pkg_meta["path"], "Versions.toml")
           versions = Pkg.TOML.parse(read(pkg_path, String))
           newest = maximum(VersionNumber.(keys(versions)))
           if newest > dep.version
               constrained[dep.name] = (dep.version, newest)
           end
       end
       return constrained
    end
end


end
