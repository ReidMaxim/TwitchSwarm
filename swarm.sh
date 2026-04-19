#!/bin/bash

# Configuration
CHANNEL="channel_name"  # Replace with your target channel
QUALITY="360p"          # Lower quality = less bandwidth
VIEWER_COUNT=3          # Number of viewers to launch
PROXY_API="https://api.proxyscrape.com/v2/?request=get&protocol=http&country=all&ssl=all&anonymity=all"

# Create directory for logs if it doesn't exist
mkdir -p ~/twitch_logs

# Function to get working proxies
get_proxies() {
    echo "Fetching fresh proxies..."
    
    # Get proxies from API and test them
    PROXIES=$(curl -s "$PROXY_API" | sed -n '1,200p' | while read -r proxy; do
        # Test proxy with timeout
        if timeout 5 curl -s --proxy "$proxy" http://ifconfig.me >/dev/null 2>&1; then
            echo "$proxy"
        fi
    done | head -n $VIEWER_COUNT)
    
    if [ -z "$PROXIES" ]; then
        echo "No working proxies found. Using Tor fallback."
        # Fallback to Tor if no proxies work
        echo "socks5://127.0.0.1:9050
socks5://127.0.0.1:9051
socks5://127.0.0.1:9052" > /tmp/proxies.txt
    else
        echo "$PROXIES" > /tmp/proxies.txt
    fi
}

# Function to start a viewer with proxy
start_viewer() {
    local proxy=$1
    local viewer_id=$2
    local log_file="$3"
    
    echo "Starting viewer $viewer_id via proxy $proxy"
    
    # Start streamlink with proxy and log output
    streamlink --http-proxy "$proxy" \
               --loglevel "info" \
               --logfile "$log_file" \
               twitch.tv/$CHANNEL \
               $QUALITY \
               --player-external-http \
               --http-output-host 127.0.0.$viewer_id \
               --http-output-port 808$viewer_id \
               > /dev/null 2>&1 &
    
    # Save the process ID
    echo $! > /tmp/viewer$viewer_id.pid
    
    echo "Viewer $viewer_id started with PID $(cat /tmp/viewer$viewer_id.pid)"
    echo "Access at http://127.0.0.$viewer_id:808$viewer_id"
}

# Main execution
echo "Starting Twitch viewer setup for channel: $CHANNEL"

# Get working proxies
get_proxies

# Read proxies and start viewers
count=1
while IFS= read -r proxy; do
    if [[ $count -le $VIEWER_COUNT ]]; then
        log_file=~/twitch_logs/viewer$count.log
        start_viewer "$proxy" $count "$log_file"
        sleep 2  # Small delay between starting viewers
        ((count++))
    fi
done < /tmp/proxies.txt

echo "All viewers started. Monitor logs in ~/twitch_logs/"
echo "To stop all viewers, run: ./stop_viewers.sh"

# Create a stop script
cat > ~/stop_viewers.sh << 'EOF'
#!/bin/bash
echo "Stopping all Twitch viewers..."

for i in {1..3}; do
    if [ -f /tmp/viewer$i.pid ]; then
        PID=$(cat /tmp/viewer$i.pid)
        if kill -0 $PID 2>/dev/null; then
            echo "Stopping viewer $i (PID $PID)"
            kill $PID
        fi
        rm -f /tmp/viewer$i.pid
    fi
done

echo "All viewers stopped."
EOF

chmod +x ~/stop_viewers.sh
