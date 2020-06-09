using IsoPkg
using Test,Pkg

group_tmp="temp_"*basename(tempname())
IsoPkg.switch(group_tmp) #Switch the current project group to a temp empty group

IsoPkg.add("Glob") #Install Glob
IsoPkg.add("Glob@1.2.0") #Install Glob v1.2.0 and pin the version

#Notice: If the following `using` statements are in the same session, only the first one does the real loading.
@iso using Glob #Load Glob
@iso using Glob "1.2.0" #Load Glob v1.2.0
@iso "Glob1" pkg"add Glob@1.3.0" #Add Glob v1.3.0 as name Glob1
@iso "Glob1" using Glob #Load Glob v1.3.0

@test readdir(IsoPkg.env_path())==["Glob","Glob1","Glob@1.2.0"]

IsoPkg.pin("Glob1")
IsoPkg.free("Glob1")
IsoPkg.pin("Glob") #Pin Glob version (will automatically change its name to match the version)
IsoPkg.free("Glob@1.2.0") #Free Glob v1.2.0 version (will automatically remove the version in its name)

IsoPkg.status() #Show status of all packages
IsoPkg.update() #Update all packages

IsoPkg.rm("Glob1") #Remove Glob v1.3.0
IsoPkg.rm("Glob") #Remove Glob
IsoPkg.rm("Glob") #Because there is only one version left, the version number can be omitted

@test readdir(IsoPkg.env_path())==[]

Base.rm(IsoPkg.env_path())
IsoPkg.switch()
