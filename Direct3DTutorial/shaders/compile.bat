@echo off
del /Q simple.vs.bin 2>NUL
del /Q simple.ps.bin 2>NUL
del /Q simple.vs.lst 2>NUL
del /Q simple.ps.lst 2>NUL
fxc.exe /nologo /Ges /O3 /T vs_4_0_level_9_0 /E main /Fo simple.vs.bin /Fc simple.vs.lst simple.vs
fxc.exe /nologo /Ges /O3 /T ps_4_0_level_9_0 /E main /Fo simple.ps.bin /Fc simple.ps.lst simple.ps