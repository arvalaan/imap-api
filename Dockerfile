FROM node:20-bookworm-slim

WORKDIR /app

COPY package*.json ./
RUN npm install --production --no-audit --no-fund

COPY . .

EXPOSE 3000

CMD ["node", "server.js", "--db.redis=redis://redis:6379/8", "--api.host=0.0.0.0", "--api.port=3000"]
