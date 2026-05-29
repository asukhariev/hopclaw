@echo off
rem Launch the HopClaw runner; run via the HopClawRunner scheduled task so it
rem survives SSH-session end (Start-Process children get killed on disconnect).
cd /d C:\hopclaw-runner\runner
node --env-file=.env index.js >> runner.log 2>&1
