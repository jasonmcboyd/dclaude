# escape=`

ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# Install Git for Windows (required by Claude Code)
ARG GIT_VERSION=2.47.1
ARG GIT_PATCH=2
RUN curl -sLo git-install.exe https://github.com/git-for-windows/git/releases/download/v%GIT_VERSION%.windows.%GIT_PATCH%/Git-%GIT_VERSION%.%GIT_PATCH%-64-bit.exe && `
    start /wait git-install.exe /VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS="gitlfs" && `
    del git-install.exe

# Install Node.js 22 LTS and Claude Code in a single step.
# setx /M persists PATH to the registry for the npm install,
# but Docker only snapshots registry PATH between RUN layers.
ARG NODE_VERSION=22.14.0
RUN curl -sLo node.zip https://nodejs.org/dist/v%NODE_VERSION%/node-v%NODE_VERSION%-win-x64.zip && `
    tar -xf node.zip && `
    move node-v%NODE_VERSION%-win-x64 C:\nodejs && `
    del node.zip && `
    setx /M PATH "C:\nodejs;%PATH%" && `
    C:\nodejs\npm install -g @anthropic-ai/claude-code

# Enable developer mode so symlinks can be created without elevation
RUN reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense /t REG_DWORD /d 1 /f

# Trust mounted workspace to avoid "dubious ownership" errors
RUN git config --global --add safe.directory C:/workspace

# Entrypoint script symlinks .claude.json from the mounted config directory
COPY entrypoint.ps1 C:\entrypoint.ps1

ENV DCLAUDE_CONTAINER=1

# Pre-create .claude directory so it's owned by the container user. Without this,
# Docker may create it when bind-mounting the project dir, and the entrypoint
# might not be able to create symlinks in it.
RUN mkdir "%USERPROFILE%\.claude"

WORKDIR C:\workspace

ENTRYPOINT ["powershell", "-NoProfile", "-File", "C:\\entrypoint.ps1"]
