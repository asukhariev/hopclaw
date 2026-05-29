@echo off
rem Self-healing HopClaw runner launcher.
rem  - This loop restarts node immediately if it exits/crashes.
rem  - The HopClawRunner scheduled task also re-triggers every few minutes with
rem    "do not start a new instance", so if the whole cmd dies it relaunches.
cd /d C:\hopclaw-runner\runner
:loop
node --env-file=.env index.js >> runner.log 2>&1
echo [%date% %time%] runner exited (code %errorlevel%), restarting in 3s >> runner.log
ping -n 4 127.0.0.1 >nul 2>&1
goto loop
