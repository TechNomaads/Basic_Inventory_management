# Production Nginx image to serve static frontend files
FROM nginx:alpine

# Copy static frontend assets into nginx HTML folder
COPY . /usr/share/nginx/html

# Expose port 80
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
