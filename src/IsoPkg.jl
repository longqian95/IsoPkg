module IsoPkg

using Pkg

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
    switch(group_name::String)
    switch()

Switch the current package group to `group_name`. If not given, switch to the default group name(the Julia version string).
"""
function switch(group_name::String=DEFAULT_GROUP)
    if group_name=="" || occursin(r"^\.*$|[/\\]",group_name)
        error("\"$group_name\" is invalid name")
    else 
        GROUP[]=group_name
    end
    return nothing
end

#Search if pkg exists in the registry
function search_registry(pkg::AbstractString)
    for registry in Pkg.Types.collect_registries()
        data = Pkg.Types.read_registry(joinpath(registry.path, "Registry.toml"))
        for (_uuid, pkgdata) in data["packages"]
            if pkg==pkgdata["name"]
                return true
            end
        end
    end
    return false
end

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
        if search_registry(name)
            error("\"$pkg\" is not installed. Use IsoPkg.add(\"$pkg\") to install it.")
        else
            error("\"$name\" is invalid (not found in registry).")
        end 
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
            m=Pkg.TOML.parsefile(joinpath(path,"Manifest.toml"))[name][1]
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
    if search_registry(name)
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
    else
        @error "\"$name\" not found in registry"
    end
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

If `force` is true, upgrade all installed packages, otherwise, update the packages which names do not include version.
"""
function update(;force=false)
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

Upgrade a package
"""
function update(pkg::AbstractString)
    @iso search_pkg(pkg).pkg Pkg.update()
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

end
