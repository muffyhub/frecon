#!/bin/bash

if [ $# -ne 1 ]; then
	echo "Usage ./runit.sh <domain>"
	echo "Example: ./runit.sh yahoo.com"
	exit 1
fi

CURRENTDATE=`date +"%Y-%m-%d_%T"`
FOLDER=$1_${CURRENTDATE}

if [ ! -d "${FOLDER}" ]; then
	mkdir ${FOLDER}
fi

cd ${FOLDER}
pwd=$(pwd)
echo $pwd

<<COMMENT
if [ ! -d "thirdlevels" ]; then
	mkdir thirdlevels
fi

if [ ! -d "fourthlevels" ]; then
	mkdir fourthlevels
fi
COMMENT

if [ ! -d "scans" ]; then
	mkdir scans
fi

if [ ! -d "eyewitness" ]; then
	mkdir eyewitness
fi

pwd=$(pwd)

echo -e "\nGathering subdomains with Subfinder..."
~/go/bin/subfinder -v -nW -d $1 -o final.txt

echo -e "\nGathering subdomains with Amass..."
amass enum -d $1 -o final_2.txt
final_2.txt >> final.txt

echo $1 >> final.txt

<<COMMENT
echo -e "\nCompiling third-level domains..."
cat final.txt | grep -Po "((?:[\w-]+)\.(?:[\w-]+)\.\w+$)" | sort -u >> third-level.txt

echo -e "\nGathering full third-level domains with Subfinder"
for domain in $(cat third-level.txt)
do 
	~/tools/subfinder/subfinder -nW -d $domain -o thirdlevels/$domain.txt
	cat thirdlevels/$domain.txt >> final.txt
done

echo -e "\nCompiling fourth-level domains..."
cat final.txt | grep -Po "((?:[\w-]+)\.(?:[\w-]+)\.(?:[\w-]+)\.\w+$)" | sort -u >> fourth-level.txt

echo -e "\nGathering full fourth-level domains with Subfinder"
for domain in $(cat fourth-level.txt)
do 
	~/tools/subfinder/subfinder -nW -d $domain -o fourthlevels/$domain.txt
	cat fourthlevels/$domain.txt >> final.txt
done
COMMENT

echo -e "\nSorting the list of subdomains"
sort -u -o final.txt final.txt

echo -e "\nProbing domains on HTTP/ HTTPS"
cat final.txt | sort -u | ~/tools/httprobe/main -c 50| tee probed.txt probed1.txt
sed -i -e 's/^http:\/\///g' -e 's/^https:\/\///g' probed.txt
sort -u -o probed.txt probed.txt

echo -e "\nCheck for Live Host: Ping Sweep"
sudo fping -f final.txt | tee live_temp.txt
cat live_temp.txt | grep alive | awk '{print $1}' >> live.txt
rm live_temp.txt

echo -e "\nCheck for Status Codes"
xargs -n1 -P 10 curl -o /dev/null --silent --head --write-out '%{url_effective}: %{http_code}\n' < probed1.txt | tee status_codes.txt

echo -e "\nConverting domain names to IP addresses"
xterm -e "~/tools/massdns/bin/massdns -r ~/Muffy/recon/resolvers_final.txt -t A -o S -w 'ip_temp.txt' 'final.txt'"
awk -F ". " '{print $3}' "ip_temp.txt" > "ip.txt"
cat ip_temp.txt
sort -u -o ip.txt ip.txt

echo -e "\nScanning for Open ports"
nmap -Pn -F --script firewall-bypass -iL ip.txt -oA scans/scanned.txt

echo -e "\nTaking Screenshots of all the subdomains"
xterm -e "~/tools/EyeWitness/Python/EyeWitness.py -f $pwd/probed.txt --web --threads 20 --timeout 25 --no-prompt -d $pwd/eyewitness/"

echo -e "\nGathering information from the wayback archieve"
~/tools/waybacktool/waybacktool.py pull --host $1| tee wayback_urls.txt

echo -e "Checking for subdomain takeover"
~/go/bin/subjack -c ~/go/src/github.com/haccer/subjack/fingerprints.json -w final.txt -t 20 -o subdomain_takeover.txt -ssl -a -v

echo -e "\nScan for $1 finished successfully"
duration=$SECONDS
echo -e "Scan completed in : $(($duration / 60)) minutes and $(($duration % 60)) seconds."
exec bash #to run the program in the target folder
