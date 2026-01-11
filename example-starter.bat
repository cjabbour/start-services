@echo off

cd C:\Projects\DotNet\start-services

REM # Start Services prompt for all options
REM powershell .\start-services.ps1

REM # Start Services with Git Pull
powershell .\start-services.ps1 -GitPull $true

REM # Start Services start with Git Pull
REM powershell .\start-services.ps1 -Action start -GitPull $true

REM # Start Services stop with Git Pull
REM powershell .\start-services.ps1 -Action stop -GitPull $true

REM # Start Services stop-one with Git Pull
REM powershell .\start-services.ps1 -Action stop-one -GitPull $true

REM # Start Services status with Git Pull
REM powershell .\start-services.ps1 -Action status -GitPull $true

PAUSE