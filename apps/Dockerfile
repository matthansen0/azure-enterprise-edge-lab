FROM node:24-alpine@sha256:50c8e8ca1d27439048670df5883f32d57cf81cff6233222c893fd0d9884cbd81
WORKDIR /app
ENV NODE_ENV=production
COPY api/package*.json ./
RUN npm ci --omit=dev --ignore-scripts \
	&& npm cache clean --force
COPY --chown=node:node api/server.js ./
COPY --chown=node:node static-site/ ./static-site/
EXPOSE 8080
ENV PORT=8080
USER node
CMD ["node", "server.js"]
