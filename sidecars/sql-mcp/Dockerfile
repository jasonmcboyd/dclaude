FROM node:22-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --production
COPY server.js .
EXPOSE 3100
HEALTHCHECK --interval=5s --timeout=3s CMD node -e "fetch('http://localhost:3100/health').then(r=>{if(!r.ok)process.exit(1)})"
CMD ["node", "server.js"]
