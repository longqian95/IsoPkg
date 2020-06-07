module IsoPkg

using Pkg

export @iso

const DEFAULT_GROUP=string("v",VERSION.major,".",VERSION.minor)

"""Name of current package group"""
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

Switch the current package group to `group_name` or to the default group name(Julia version).
"""
function switch(group_name::String=DEFAULT_GROUP)
    if group_name==""
        error("invalid group name")
    else 
        GROUP[]=group_name
    end
    return nothing
end

#Search if pkg exists in registry
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

#Search if pkg installed. If installed, return the detailed information, otherwise raise error.
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

# Examples

    #Load Glob
    @iso using Glob

    #Load UnicodePlots v1.2.0 (after IsoPkg.add("UnicodePlots@1.2.0"))
    @iso using UnicodePlots "1.2.0"

    #Pin Glob version
    @iso "Glob" Pkg.pin("Glob")

    #Show Glob status (equivalent to IsoPkg.status("Glob"))
    @iso "Glob" pkg"status --manifest"
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

If `pkg` is in the "name@ver" form, then add it and pin the version. If want to free it, just use `IsoPkg.rm(name); IsoPkg.add(name)`. Because the `pkg` is in fact just an environment, these operations are quite lightweight. `@iso name pkg"free name"` can also be used to free it. This way is not recommended because the "ver" in package name may not match the real package version after package updating.

# Examples

    #install Glob
    IsoPkg.add("Glob")

    #install Glob v1.2.0 and pin the version
    IsoPkg.add("Glob@1.2.0")
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

Remove a package.
"""
function rm(pkg::AbstractString)
    Base.rm(search_pkg(pkg).path; recursive=true)
    return nothing
end

"""
    update()
    update(pkg::AbstractString)

Upgrade a package or all installed packages.
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

#Get detailed information of pkg according to Project.toml and Manifest.toml
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

Show the status of a package or all installed packages.
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

function test()
    @eval begin
        IsoPkg.switch("test") #switch current project group to "test"
        IsoPkg.add("Glob") #install Glob
        IsoPkg.add("Glob@1.2.0") #install Glob v1.2.0 and pin the version
        @iso using Glob #load Glob
        @iso using Glob "1.2.0" #load Glob v1.2.0
        @iso "Glob1" pkg"add Glob@1.3.0" #add Glob v1.3.0 as name Glob1
        @iso "Glob1" using Glob #load Glob v1.3.0
        IsoPkg.status() #show status
        IsoPkg.update() #update all packages
        IsoPkg.rm("Glob1") #remove Glob v1.3.0
        IsoPkg.switch()
    end
end

end