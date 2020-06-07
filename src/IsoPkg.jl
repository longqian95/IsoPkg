module IsoPkg

using Pkg

export @iso

"""package group name"""
const GROUP=Ref(string("v",VERSION.major,".",VERSION.minor))

function env_path()
    depots=Pkg.depots1()
    pos="env_isolated_packages"
    p=joinpath(Pkg.depots1(),pos,GROUP[])
    isdir(p) || mkpath(p)
    return p
end

"""
    switch(group_name::String)

Switch the current package group to `group_name`.
"""
function switch(group_name::String)
    if group_name==""
        error("invalid group name")
    else 
        GROUP[]=group_name
    end
    return nothing
end

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
        p=Pkg.PackageSpec(name=name,version=VersionNumber(ver))
    else
        name,ver=pkg,""
        p=Pkg.PackageSpec(name=pkg)
    end
    return (name=name,ver=ver,spec=p)
end

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

function activate(pkg::AbstractString)
    Pkg.activate(joinpath(env_path(),pkg))
end

"""
    @iso(using_or_import_statement)
    @iso(using_or_import_statement, version_string)
    @iso(pkg_name, statement)

Load package or run `statement` in the specified package environment.

Currently it does not support multiple package loading.
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
            cur_proj=dirname(Pkg.Types.find_project_file())
            try
                activate($(esc(expr1)))
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

If `pkg` is "name@ver" form, then add it and pin the version. If want to free it, just use `IsoPkg.rm(name); IsoPkg.add(name)`. Because the `pkg` is in fact just an environment, these operations are quite lightweight. `@iso name pkg"free name"` can also free it and is not recommended because the environment name and the package name will not match after package updating.
"""
function add(pkg::AbstractString)
    name,ver,spec=str2spec(pkg)
    if search_registry(name)
        @iso pkg ver=="" ? Pkg.add(spec) : (Pkg.add(spec);Pkg.pin(name))
    else
        @error name * " not found"
    end
    return nothing
end

"""
    rm(pkg::AbstractString)

Remove package
"""
function rm(pkg::AbstractString)
    Base.rm(search_pkg(pkg).path; recursive=true)
    return nothing
end

"""
    update()
    update(pkg::AbstractString)

Upgrade the specified package or all installed packages
"""
function update()
    for pkg in readdir(env_path())
        @iso pkg Pkg.update()
    end
    return nothing
end

function update(pkg::AbstractString)
    @iso search_pkg(pkg).pkg Pkg.update()
    return nothing
end

function pkg_info(pkg::AbstractString)
    path=joinpath(env_path(),pkg)
    name=uuid=ver=""

    try
        p=Pkg.TOML.parsefile(joinpath(path,"Project.toml"))
        name,uuid=first(p["deps"])
    catch
    end

    try
        m=Pkg.TOML.parsefile(joinpath(path,"Manifest.toml"))
        ver=m[name][1]["version"]
    catch
    end

    return (name=name,uuid=uuid,ver=ver)
end

"""
    status()
    status(pkg::AbstractString)

Show the status of the specified package or all installed packages
"""
function status()
    for pkg in readdir(env_path())
        p=pkg_info(pkg)
        u = p.uuid=="" ? ' '^8 : p.uuid[1:8]
        u = "["*u*"]"
        v = p.ver=="" ? "" : "v"*p.ver
        s=u*" "*pkg
        if pkg==p.name
            s*=" ("*v*")"
        elseif pkg!=p.name*"@"*p.ver
            s*=" ("*p.name*" - "*v*")"
        end
        println(s)
    end
    return nothing
end

function status(pkg::AbstractString)
    @iso search_pkg(pkg).pkg Pkg.status(mode=PKGMODE_MANIFEST)
    return nothing
end


end