FROM node:20-alpine AS build

WORKDIR /app
COPY package.json .
RUN npm install
COPY src/ src/
COPY public/ public/
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/build /usr/share/nginx/html
EXPOSE 80 443
CMD ["nginx", "-g", "daemon off;"]
