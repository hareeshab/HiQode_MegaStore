FROM node:18-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci || npm i
COPY . .
EXPOSE 8004
CMD ["npm","start"]
