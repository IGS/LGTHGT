#!/bin/bash

echo "----------------------------------------------------------------------------------------------------"
echo -e "\nWelcome to the LGTView installer. Please follow the prompts below that will help configure the security level of the site."
echo -e "\n\n*** PLEASE NOTE ***"
echo -e "\nWhile there are various options here present to try and protect your data, YOU MUST VERIFY that the security is up to your standards before loading a sensitive dataset."
echo -e "\n*******************\n"

# At this point need to download a few files that are going to be mounted via
# docker-compose so that MongoDB can be initiated with the necessary taxonomy data
echo "Setting up the necessary local directories and files for MongoDB and TwinBLAST......"
if [ ! -d "/home/lgtview/files_for_mongo_and_twinblast" ]; then
	mkdir -p /home/lgtview/files_for_mongo_and_twinblast
	chmod 777 /home/lgtview/files_for_mongo_and_twinblast
fi

if [ ! -f "/home/lgtview/files_for_mongo_and_twinblast/example_metadata.out" ]; then
	wget -O /home/lgtview/files_for_mongo_and_twinblast/example_metadata.out https://sourceforge.net/projects/lgthgt/files/example_metadata.out/download
fi
if [ ! -f "/home/lgtview/files_for_mongo_and_twinblast/example_blastn.out" ]; then
	wget -O /home/lgtview/files_for_mongo_and_twinblast/example_blastn.out https://sourceforge.net/projects/lgthgt/files/example_blastn2.out/download
fi

echo -e "\nDone Setting up the necessary local directories and files for MongoDB."

echo "----------------------------------------------------------------------------------------------------"

echo -e "\nWould you like to add SSL (via self-signed certificate) to encrypt transmitted sensitive data? Entering 'yes' is highly recommended. Entering 'no' is alright if this instance will not be hosted on a network and just on your own machine for your own use. Please enter 'yes' or 'no': "
read ssl_response 

# If the user wants to use SSL, close out the other ports during the build phase.
if [ "$ssl_response" = 'yes' ]
then
	sed -i "/8080\:80/d" docker-compose.yml
	sed -i "/EXPOSE 80/d" ./docker_LGTView/Dockerfile
else
	sed -i "/443\:443/d" docker-compose.yml
	sed -i "/EXPOSE 443/d" ./docker_LGTView/Dockerfile
fi

echo "----------------------------------------------------------------------------------------------------"

echo -e "\nGoing to build and run the Docker containers now......"

# Now, establish the following Docker containers:
# 1. lgthgt_LGTview_1
#  - Houses the Apache server and LGTview related code
# 2. lgthgt_mongo_1
#  - Houses the MongoDB server
# 3. lgthgt_mongodata_1
#  - A container to establish persistent MongoDB data
# 4. lgthgt_R_1
#  - Houses the R package and necessary dependencies
docker-compose up -d

echo -e "\n----------------------------------------------------------------------------------------------------"
echo "Docker containers done building and ready to go! Please follow the rest of the installation prompts."
echo -ne "\n----------------------------------------------------------------------------------------------------"

# Ask the user whether they want their site to be password protected
echo -ne "\nWould you like to add password protection for viewing access to the LGTView site? Entering 'yes' is highly recommended. Entering 'no' is alright if this instance will not be hosted on a network and just on your own machine for your own use. Please enter 'yes' or 'no': "
read response 
if [ "$response" = 'yes' ]; then

		echo -ne "Please enter the desired username for accessing LGTView: "
		read username
		echo -ne "Please enter the desired password for the username $username: "
		read -s password
		echo -ne "\nPlease re-enter the password: "
		read -s password_confirm

	while [ "$password" != "$password_confirm" ]; do

		echo -ne "\nPasswords do not match. Please re-enter the password: "
		read -s password_confirm

	done

	echo -e "\nAdding username and password protection to the site, just one moment..."

	# Go into the Apache container and configure for passwords. Here, respond to the
	# two interactive prompts using the supplied passwords.
	docker exec -it lgthgt_LGTView_1 htpasswd -cb /etc/apache2/.htpasswd "$username" "$password_confirm"

	# Now configure the necessary Apache confs to accommodate this protected setup.
	docker exec -it lgthgt_LGTView_1 sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
	# Just in case the installer has failed, clear the file and start anew
	rm ./.htaccess
	printf '%s\n%s\n%s\n%s' 'AuthType Basic' 'AuthName "Restricted Content"' 'AuthUserFile /etc/apache2/.htpasswd' 'Require valid-user' >> ./.htaccess
	docker cp ./.htaccess lgthgt_LGTView_1:/var/www/html/.htaccess

	# Restart the Apache container with this new configuration
	docker exec -it lgthgt_LGTView_1 /etc/init.d/apache2 reload
	echo "Login requirement added. Please be sure to save this information somewhere so that you do not lose access to the site."
fi

echo -e "----------------------------------------------------------------------------------------------------"
if [ "$ssl_response" = 'yes' ]
then
	docker exec -it lgthgt_LGTView_1 sed -i '8s@443@443 https@' /etc/apache2/ports.conf
	docker exec -it lgthgt_LGTView_1 sed -i '5s@Listen 80@#Listen 80@' /etc/apache2/ports.conf
	docker exec -it lgthgt_LGTView_1 /etc/init.d/apache2 reload

	echo -n "Please answer the following in order to complete the SSL setup (https) for the site."
	echo -ne "\nCountry Name (2 letter code) [US]: "
	read country
	echo -ne "State or Province Name (full name) [New York]: "
	read state
	echo -ne "Locality Name (eg, city) [New York City]: "
	read city
	echo -ne "Organization Name (eg, company) [University of Maryland]: "
	read organization
	echo -ne "Organizational Unit Name (eg, section) [Institute for Genome Sciences]: "
	read division
	echo -ne "Email for setup contact [the_best_email@domain.com]: "
	read email
	docker exec -it lgthgt_LGTView_1 openssl req -x509 -nodes -days 1460 -newkey rsa:2048 \
		-keyout /etc/apache2/ssl/apache.key -out /etc/apache2/ssl/apache.crt \
		-subj "/C=$country/ST=$statei/L=$city/O=$organization/OU=$division/CA=TRUE/CN=localhost"

	# Modify the confs to use the newly generated SSL cert+key
	docker exec -it lgthgt_LGTView_1 sed -i '32s@/etc/ssl/certs/ssl-cert-snakeoil.pem@/etc/apache2/ssl/apache.crt@' /etc/apache2/sites-available/default-ssl.conf
	docker exec -it lgthgt_LGTView_1 sed -i '33s@/etc/ssl/private/ssl-cert-snakeoil.key@/etc/apache2/ssl/apache.key@' /etc/apache2/sites-available/default-ssl.conf
	docker exec -it lgthgt_LGTView_1 sed -i "3s/webmaster@localhost/$email/" /etc/apache2/sites-available/default-ssl.conf
	docker exec -it lgthgt_LGTView_1 sed -i "3a\\\t\tServerName localhost" /etc/apache2/sites-available/default-ssl.conf
	docker exec -it lgthgt_LGTView_1 sed -i "4a\\\t\tServerAlias lgtview" /etc/apache2/sites-available/default-ssl.conf
	docker exec -it lgthgt_LGTView_1 sed -i "1s/^/Listen 443\n/" /etc/apache2/sites-available/default-ssl.conf

	# Set this new SSL conf and restart Apache one last time. SSL should now be enabled
	docker exec -it lgthgt_LGTView_1 a2ensite default-ssl.conf
	docker exec -it lgthgt_LGTView_1 /etc/init.d/apache2 reload
	echo -ne "SSL now implemented (access site through https)."
	docker exec -it lgthgt_LGTView_1 sed -i "/localhost\:8080/d" /var/www/html/lgtview.js
else
	echo -ne "SSL NOT implemented (access site through http). Transmitted data is potentially subject to eavesdropping."
	docker exec -it lgthgt_LGTView_1 sed -i "/localhost\:443/d" /var/www/html/lgtview.js
fi
echo -e "\n----------------------------------------------------------------------------------------------------"

# Make sure the MongoDB server container is up and running
UP1=$(docker ps -a | grep 'mongo:2.6' | grep 'Up' | wc -l);
while [ "$UP1" -ne 1 ]; do
	UP1=$(docker ps -a | grep 'mongo:2.6' | grep 'Up' | wc -l);
	sleep 5
done

echo "Going to load example data into MongoDB..."
docker exec -it lgthgt_LGTView_1 perl /usr/bin/lgt_load_mongo.pl --metadata=/files_for_mongo_and_twinblast/example_metadata.out --db=lgtview_example --host=172.18.0.1:27017
echo "MongoDB loaded."

docker exec -it lgthgt_LGTView_1 cp /files_for_mongo_and_twinblast/example_blastn.out /export/lgt/files/.

echo -e "\n----------------------------------------------------------------------------------------------------"
echo -e "\nLGTView installation completed.\n"
