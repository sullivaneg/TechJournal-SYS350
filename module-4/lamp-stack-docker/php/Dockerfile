FROM php:8.2-apache

# Install necessary PHP extensions for MySQL
RUN docker-php-ext-install pdo_mysql mysqli

# (Optional) Install other common extensions
# RUN docker-php-ext-install gd opcache

# Copy your application code into the container
# Note: We also mount this via volume in compose, but copying is good for production builds
COPY src/ /var/www/html/

# Set permissions
RUN chown -R www-data:www-data /var/www/html
