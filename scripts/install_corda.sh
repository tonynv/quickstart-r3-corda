# Need to add verfication logic
echo "Starting Corda Install"
sudo adduser --system --no-create-home --group corda
sudo mkdir /opt/corda; sudo chown corda:corda /opt/corda
cd /opt/corda
sudo wget -O corda.jar https://r3.bintray.com/corda/net/corda/corda/1.0.0/corda-1.0.0.jar
sudo wget -O corda-webserver.jar http://r3.bintray.com/corda/net/corda/corda-webserver/1.0.0/corda-webserver-1.0.0.jar
sudo mkdir /opt/corda/cordapps
