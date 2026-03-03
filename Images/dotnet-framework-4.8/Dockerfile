# escape=`

FROM mcr.microsoft.com/dotnet/framework/sdk:4.8.1-windowsservercore-ltsc2022

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# Install Node.js 22 LTS via zip extraction
ARG NODE_VERSION=22.14.0
RUN Invoke-WebRequest -Uri "https://nodejs.org/dist/v$env:NODE_VERSION/node-v$env:NODE_VERSION-win-x64.zip" -OutFile node.zip; `
    Expand-Archive node.zip -DestinationPath C:\; `
    Rename-Item "C:\node-v$env:NODE_VERSION-win-x64" C:\nodejs; `
    Remove-Item node.zip -Force

ENV PATH="C:\nodejs;${PATH}"

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code

WORKDIR C:\workspace

ENTRYPOINT ["claude", "--dangerously-skip-permissions"]
