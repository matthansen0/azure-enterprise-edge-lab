FROM node:20-alpine
WORKDIR /app
COPY api/package*.json ./
RUN npm ci --omit=dev
COPY api/server.js ./
COPY static-site/ ./static-site/
EXPOSE 8080
ENV PORT=8080
CMD ["node", "server.js"]
