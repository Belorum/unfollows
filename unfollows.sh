#!/bin/bash
# Get email notifications about Twitter unfollowers
# This script will work for Twitter accounts with up to 5000 followers

#Checks to see if cURL is installed and if not installs it

if command -v curl >/dev/null 2>&1; then
	echo Curl is already installed, moving to the next step.
else
	sudo apt-get install curl;
fi

#Downloads OAuth_sign, extracts it and then remove tar file

echo " "
wget http://acme.com/software/oauth_sign/oauth_sign_14Aug2014.tar.gz && tar -xzf oauth_sign_14Aug2014.tar.gz;

rm oauth_sign_14Aug2014.tar.gz

#Downloads Binaries file JSON parser for the CLI
wget https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 && mv jq-linux64 jq

#Makes jq file executable
chmod 700 jq

# Set your configuration

#Added user input for variable fields
read -p 'Enter email address for notifications: ' mail # Where should notifications arrive?
read -p 'Enter email address notifications should come from: ' frommail # Where should notifications come from?
read -p 'Enter your Twitter Username: ' screen_name # Your Twitter username

read -p 'Do you need to setup your Twitter App? <y/n> ' twitter_app_setup

# NEEDS TO BE FIXED
#if %twitter_app_setup%=='y'; then #Checks if user needs to set up their twitter app then attempts to open an appropriate browser
#	echo "Go to this website and log in to create you app key and tokens: https://apps.twitter.com/app/new"
#	read -p 'Would you like to go there now? ' setup_app
#	if %setup_app%=='y'; then
#		if [ -n $BROWSER ]; then
#			$BROWSER 'https://apps.twitter.com/app/new'
#		elif which xdg-open > /dev/null; then
#			xdg-open 'https://apps.twitter.com/app/new'
#		elif which gnome-open > /dev/null; then
#			gnome-open 'https://apps.twitter.com/app/new'
#		else
#			echo "Could not detect the web browser to use."
#			echo "Please go to this web address: https://apps.twitter.com/app/new"
#		fi
#		echo "Fill out the form then click on 'Manage Keys and Access Tokens'"
#		echo "Copy your 'Consumer Key and Consumer Secret for later'"
#		echo "Click on 'Create Access Token' and copy this information also"
#		echo "Change permissions under the 'Permissions' tab to 'Read Only'"
#		echo "Remember to keep all of this information secret and do not post online."
#	fi
#fi

#Adding variable fields for Twitter App
echo "Consumer Key" Format - xxxxxxxxxxxxxxxxxxxxxxxxx
read -p 'Enter your Consumer Key: ' consumer_key
echo
echo "Consumer Key Secret" Format - xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
read -p 'Enter your Consumer Key Secret: ' consumer_key_secret
echo
echo "Access Token" Format - xxxxxxxx-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
read -p 'Enter your Access Token:' token
echo
echo "Access Token Secret" Format - xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
read -p 'Enter your Access Token Secret: ' token_secret

#End of User Input

# You can stop editing here :)


method="GET"
basedir=$(dirname $0)
mkdir $basedir/out 2>/dev/null
newids="$basedir/out/newids.txt"
oldids="$basedir/out/oldids.txt"
unfollowerids="$basedir/out/unfollowerids.txt"
unfollowernames="$basedir/out/unfollowernames.txt"
unfollowers="$basedir/out/unfollowers.txt"
mailtmp="$basedir/out/mailtmp.txt"

# Get our follower's ids
followers_url="https://api.twitter.com/1.1/followers/ids.json?screen_name=$screen_name"
followers_oauth_sign=$($basedir/oauth_sign $consumer_key $consumer_key_secret $token $token_secret $method $followers_url)
curl -s --request $method $followers_url --header "Authorization: $followers_oauth_sign" | $basedir/jq '.ids' | tr -d '[], ' | grep . > $newids

# Check if the query was successful
# A bit hackish, basically checks if there is something which looks like an ID
if ! grep -E -q -i -o "[0-9]{7,999}" $newids ; then
	exit
fi

# If it's the first time, we don't want to spam our inbox
if [[ ! -f $oldids ]]; then
	cp $newids $oldids
	exit
fi

# Get our unfollowers
cat $newids $newids $oldids | sort | uniq -u > $unfollowerids

# Prepare for the next run
rm -f $oldids
cp $newids $oldids

# If we got unfollowers, match their IDs with screen names
if [[ -s $unfollowerids ]] ; then
	# cleanup
	rm -f $unfollowernames
	while read line; do
		# lookup the screen_name of the ids
		lookup_url="https://api.twitter.com/1.1/users/lookup.json?user_id=$line"
		lookup_oauth_sign=$($basedir/oauth_sign $consumer_key $consumer_key_secret $token $token_secret $method $lookup_url)
		curl -s --request $method $lookup_url --header "Authorization: $lookup_oauth_sign" | $basedir/jq .[]'.screen_name' | tr -d '"' >> $unfollowernames
	done < $unfollowerids
else
	# If we haven't unfollowers, we're done.
	exit
fi

# jq will cry if we pass the json from a deleted user. Remove blank lines too.
grep -v 'jq: error: Cannot index array with string' $unfollowernames | grep . > $unfollowers

# If we matched some ids to screen names, send the mail
if [[ -s $unfollowers ]] ; then
	    echo "Hi $screen_name", > $mailtmp
	    echo >> $mailtmp
	    echo "The following people aren't following you any longer:" >> $mailtmp
	    echo >> $mailtmp
	    cat $unfollowers | sed -e 's#^#https://twitter.com/#' >> $mailtmp
	    mail -a "From: $frommail" -s "Someone has unfollowed you" $mail < $mailtmp
fi
