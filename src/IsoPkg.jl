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
        ver=string(VersionNumber(ver))
        p=Pkg.PackageSpec(name=name,version=ver)
    else
        name,ver=pkg,""
        p=Pkg.PackageSpec(name=pkg)
    end
    return (name=name,ver=ver,spec=p)
end

#Search if pkg installed. If installed, return (pkg,name,ver,path), otherwise raise error.
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

#Get detailed information of pkg according to Project.toml and Manifest.toml
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
        error("\"$pkg\" is invalid")
    else
        @info "New \"$pkg\""
        Pkg.activate(joinpath(env,pkg))
    end
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

If `pkg` is in the "name@ver" form, then add the specified version and pin it.

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

"""
    status()
    status(pkg::AbstractString)

Show the status of a package or all installed packages.
"""
function status()
    for pkg in readdir(env_path())
        p=pkg_info(pkg)
        u = p.uuid=="" ? ' '^8 : p.uuid[1:8]
        u = "[$u]"
        v = p.ver=="" ? "" : "v"*p.ver
        pin = p.pinned ? " ⚲" : ""
        print(u," "); printstyled(pkg,bold=true,color=:light_blue)
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
        error("cannot get the version of \"$pkg\"")
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
        error("cannot get the version of \"$pkg\"")
    end
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
        IsoPkg.pin("Glob1")
        IsoPkg.free("Glob1")
        IsoPkg.pin("Glob")
        IsoPkg.free("Glob@1.2.0")
        IsoPkg.rm("Glob1") #remove Glob v1.3.0
        IsoPkg.switch()
    end
end

end