#!/usr/bin/env bash
set -euo pipefail

# If not root, re-exec this script under sudo
if [ "$EUID" -ne 0 ]; then
  echo "⚠️  This script requires root privileges. Attempting to sudo..."
  sudo -v                              # prompt for password up front
  exec sudo bash "$0" "$@"             # re-run as root
fi

# Complete Cleanup and Fresh Installation Script for Chrome OS
# Includes bootstrap system, security tools, utilities, and navigation

set -euo pipefail
echo "===== CHROME OS COMPLETE CLEANUP AND FRESH INSTALL ====="

# Create a dedicated log file and setup error detection
detect_chromeos_errors() {
  echo "Running Chrome OS error detection..."
  
  # Check if running on Chrome OS
  if [ -f /etc/lsb-release ] && grep -q "Chrome OS" /etc/lsb-release; then
    echo "  [+] Confirmed running on Chrome OS"
  else
    echo "  [!] WARNING: Not running on Chrome OS, some features may not work correctly"
  fi
  
  # Check disk space
  disk_space=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
  if [ "$disk_space" -gt 90 ]; then
    echo "  [!] ERROR: Low disk space ($disk_space% used)"
  else
    echo "  [+] Disk space is adequate ($disk_space% used)"
  fi
  
  # Check memory
  mem_avail=$(free -m | awk '/^Mem:/ {print $7}')
  if [ "$mem_avail" -lt 500 ]; then
    echo "  [!] ERROR: Low memory available (${mem_avail}MB free)"
  else
    echo "  [+] Memory is adequate (${mem_avail}MB free)"
  fi
  
  # Check container features
  if [ ! -S /var/run/docker.sock ]; then
    echo "  [!] ERROR: Docker socket not found, container features may not be enabled"
  fi
  
  # Check ChromeOS integration
  if [ ! -d /mnt/chromeos ]; then
    echo "  [!] WARNING: ChromeOS integration directory not found"
  fi
  
  # Check network connectivity
  if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo "  [!] ERROR: Network connectivity issue detected"
  else
    echo "  [+] Network connectivity verified"
  fi
  
  echo "Chrome OS error detection completed"
}

# Run error detection at startup
detect_chromeos_errors
LOG_FILE="/tmp/clean-install.log"
touch $LOG_FILE
exec > >(tee -a $LOG_FILE) 2>&1

echo "[$(date)] Starting complete cleanup and fresh installation..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)."
  exit 1
fi

### PART 1: COMPLETE CLEANUP ###
echo "[CLEANUP] Removing all previous configurations..."

# Stop all related services and containers
echo "  [+] Stopping all services and containers..."
systemctl stop device-auth-engine.service 2>/dev/null || true
systemctl stop device-auth-learn.service 2>/dev/null || true
systemctl stop device-auth-verify.timer 2>/dev/null || true
systemctl stop falco.service 2>/dev/null || true
systemctl stop auditd.service 2>/dev/null || true
docker stop falco 2>/dev/null || true
docker rm falco 2>/dev/null || true

# Remove previous falco installation completely
echo "  [+] Removing Falco..."
apt-get remove --purge -y falco falcosecurity-archive-keyring dkms 2>/dev/null || true
rm -rf /etc/falco /etc/apt/sources.list.d/*falco* /usr/src/falco* /var/lib/dkms/falco* 2>/dev/null || true

# Remove bootstrap directories
echo "  [+] Removing bootstrap directories..."
for NS in auth net git services projects emv utils devlinks; do
  rm -rf "/$NS" 2>/dev/null || true
  echo "  [-] Removed /$NS"
done

# Remove systemd services
echo "  [+] Removing systemd services..."
rm -f /etc/systemd/system/device-auth-engine.service 2>/dev/null || true
rm -f /etc/systemd/system/device-auth-learn.service 2>/dev/null || true
rm -f /etc/systemd/system/device-auth-verify.timer 2>/dev/null || true
rm -f /etc/systemd/system/device-auth-verify.service 2>/dev/null || true
rm -f /etc/systemd/system/falco.service 2>/dev/null || true

# Remove utility scripts
echo "  [+] Removing utility scripts..."
rm -f /usr/local/bin/security-dashboard.sh 2>/dev/null || true
rm -f /usr/local/bin/falco-control.sh 2>/dev/null || true
rm -f /usr/local/bin/falco-alert.sh 2>/dev/null || true
rm -f /usr/local/bin/security-check.sh 2>/dev/null || true
rm -f /usr/local/bin/security-workflow.sh 2>/dev/null || true
rm -f /usr/local/bin/security-fix.sh 2>/dev/null || true
rm -f /usr/local/bin/navigate.sh 2>/dev/null || true
rm -f /usr/local/bin/utils.sh 2>/dev/null || true
rm -f /usr/local/bin/help.sh 2>/dev/null || true

# Remove docker bench security
echo "  [+] Removing Docker Bench Security..."
rm -rf /home/*/docker-bench-security 2>/dev/null || true

# Remove audit rules
echo "  [+] Removing audit rules..."
rm -f /etc/audit/rules.d/docker* 2>/dev/null || true

# Reset crontab if it contains our entries
echo "  [+] Resetting crontab..."
(crontab -l 2>/dev/null | grep -v "find /services/verify/log" | crontab -) || true

# Remove aliases and profile scripts
rm -f /etc/profile.d/custom-aliases.sh 2>/dev/null || true
rm -f /etc/profile.d/utils-path.sh 2>/dev/null || true
rm -f /etc/bash_completion.d/custom_completion 2>/dev/null || true

# Reload systemd
systemctl daemon-reload
echo "[CLEANUP] Complete! All previous configurations have been removed."

### PART 2: FRESH BOOTSTRAP INSTALLATION ###
echo "[INSTALL] Starting fresh installation..."

# Define environment variables
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export BOOT_ROOT="/"
export CONFIG_DIR="/etc"
export BIN_DIR="/usr/local/bin"
export LOG_DIR="/var/log/device-auth"
export SERVICE_DIR="/etc/systemd/system"
export LINK_HUB="/devlinks"

# Create fresh namespaces
echo "  [+] Creating fresh namespaces..."
for NS in auth net git services projects emv; do
  mkdir -p "/$NS/config" "/$NS/bin" "/$NS/lib" "/$NS/log" "/$NS/tmp"
done

mkdir -p "$LINK_HUB"
ln -sfn /auth "$LINK_HUB/auth"
ln -sfn /net "$LINK_HUB/net"
ln -sfn /git "$LINK_HUB/git"
ln -sfn /services "$LINK_HUB/services"
ln -sfn /projects "$LINK_HUB/projects"
ln -sfn /emv "$LINK_HUB/emv"

# Create additional service directories
mkdir -p /services/verify/config /services/verify/bin /services/verify/log
mkdir -p /services/learn/config /services/learn/bin /services/learn/log 
mkdir -p /services/self-heal/config /services/self-heal/bin /services/self-heal/log

### PART 3: DOCKER PROPER INSTALLATION ###
echo "[INSTALL] Installing Docker properly..."

# Install prerequisites
echo "  [+] Installing prerequisites..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release uidmap dbus-user-session

# Add Docker's official GPG key & repo with proper error handling
echo "  [+] Setting up Docker repositories..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker components
echo "  [+] Installing Docker components..."
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Configure Docker for security
echo "  [+] Configuring Docker for security..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'DOCKERJSON'
{
  "icc": false,
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "dns": ["8.8.8.8", "8.8.4.4"]
}
DOCKERJSON

# Restart Docker service
systemctl restart docker
echo "  [+] Docker installation completed"

# Add current user to docker group
usermod -aG docker $(logname) 2>/dev/null || true
echo "  [+] Added user $(logname) to docker group"

### PART 4: FALCO SECURITY SETUP ###
echo "[INSTALL] Setting up Falco security monitoring..."

# Setup Falco directories and configuration
mkdir -p /etc/falco/rules.d
echo "  [+] Created Falco configuration directories"

# Setup Falco configuration
cat > /etc/falco/falco.yaml << 'FALCOYAML'
driver:
  enabled: true
  kind: ebpf
stdout_output:
  enabled: true
file_output:
  enabled: true
  filename: /var/log/falco.log
program_output:
  enabled: false
http_output:
  enabled: false
FALCOYAML
echo "  [+] Created Falco configuration file"

# Create custom rules for Chrome OS
cat > /etc/falco/rules.d/chrome-os-custom.yaml << 'FALCORULES'
- rule: Chrome OS Container Escape Attempt
  desc: Detect attempts to escape from container to host
  condition: evt.type=open and fd.name startswith /proc/ and not proc.name in (falco, sshd, systemd)
  output: "Container Escape Attempt (user=%user.name command=%proc.cmdline file=%fd.name)"
  priority: WARNING

- rule: Sensitive File Access
  desc: Detect access to sensitive files in container
  condition: evt.type=open and fd.name in (/etc/shadow, /etc/passwd, /etc/ssh/sshd_config, /etc/sudoers)
  output: "Sensitive File Accessed (user=%user.name command=%proc.cmdline file=%fd.name)"
  priority: WARNING

- rule: Docker Socket Access
  desc: Detect access to Docker socket
  condition: fd.name=/var/run/docker.sock and not proc.name in (docker, dockerd, containerd)
  output: "Unauthorized Docker Socket Access (user=%user.name command=%proc.cmdline)"
  priority: WARNING

- rule: Unexpected Network Activity
  desc: Detect unexpected network connections to sensitive ports
  condition: evt.type=connect and (fd.lport in (22, 3306, 6379, 27017) or fd.rport in (22, 3306, 6379, 27017))
  output: "Unexpected Network Connection (user=%user.name command=%proc.cmdline connection=%fd.name)"
  priority: NOTICE

- rule: Container Shell Activity
  desc: Detect shell commands inside container
  condition: container.id != host and proc.name in (bash, sh, zsh)
  output: "Shell activity in container (container=%container.id user=%user.name command=%proc.cmdline)"
  priority: NOTICE

- rule: Namespace Access
  desc: Detect unauthorized access to bootstrap namespaces
  condition: evt.type=open and fd.directory in (/auth, /net, /git, /services, /projects, /emv) and not user.name="root"
  output: "Unauthorized namespace access (user=%user.name command=%proc.cmdline directory=%fd.directory)"
  priority: WARNING
FALCORULES
echo "  [+] Created custom security rules"

# Set up Falco Docker container
echo "  [+] Setting up Falco container..."
docker pull falcosecurity/falco:latest
docker rm -f falco 2>/dev/null || true
docker run -d --name falco \
  --restart always \
  --privileged \
  -v /var/run/docker.sock:/host/var/run/docker.sock \
  -v /dev:/host/dev \
  -v /proc:/host/proc:ro \
  -v /boot:/host/boot:ro \
  -v /lib/modules:/host/lib/modules:ro \
  -v /usr:/host/usr:ro \
  -v /etc/falco/rules.d:/etc/falco/rules.d:ro \
  falcosecurity/falco:latest

# Verify Falco container is running
if docker ps | grep -q falco; then
  echo "  [+] Falco container successfully started"
else
  echo "  [!] WARNING: Falco container failed to start. Will retry in self-healing script."
fi

### PART 5: BOOTSTRAP SERVICES ###
echo "[INSTALL] Creating system services..."

# Create self-healing script
cat > /services/self-heal/bin/self-healing-engine.sh << 'SELFHEAL'
#!/bin/bash
# Self-healing engine script
LOG_FILE="/services/self-heal/log/engine.log"

function log_message() {
  echo "[$(date)] $1" >> $LOG_FILE
}

function check_docker() {
  if ! systemctl is-active --quiet docker; then
    log_message "Docker service is down. Attempting to restart..."
    systemctl restart docker
  fi
}

function check_falco() {
  if ! docker ps | grep -q falco; then
    log_message "Falco container is down. Attempting to restart..."
    docker start falco || docker run -d --name falco --restart always --privileged \
      -v /var/run/docker.sock:/host/var/run/docker.sock \
      -v /dev:/host/dev -v /proc:/host/proc:ro -v /boot:/host/boot:ro \
      -v /lib/modules:/host/lib/modules:ro -v /usr:/host/usr:ro \
      -v /etc/falco/rules.d:/etc/falco/rules.d:ro \
      falcosecurity/falco:latest
  fi
}

function check_permissions() {
  # Verify critical directories have correct permissions
  for dir in /auth /net /git /services /projects /emv /utils; do
    if [ -d "$dir" ] && [ "$(stat -c %a $dir)" != "755" ]; then
      log_message "Incorrect permissions on $dir. Fixing..."
      chmod 755 $dir
    fi
  done
}

function check_symlinks() {
  # Check devlinks symlinks
  for link in auth net git services projects emv utils; do
    if [ ! -L "/devlinks/$link" ] || [ ! -e "/devlinks/$link" ]; then
      log_message "Broken symlink /devlinks/$link. Fixing..."
      ln -sfn "/$link" "/devlinks/$link"
    fi
  done
}

# Main loop
mkdir -p "$(dirname $LOG_FILE)"
log_message "Self-healing engine started"
while true; do
  check_docker
  check_falco
  check_permissions
  check_symlinks
  sleep 300  # Check every 5 minutes
done
SELFHEAL
chmod +x /services/self-heal/bin/self-healing-engine.sh
echo "  [+] Created self-healing engine script"

# Create learning script
cat > /services/learn/bin/adaptive-learning.py << 'LEARNING'
#!/usr/bin/env python3
# Simple adaptive learning engine
import time
import os
import sys
import datetime
import subprocess
import json

LOG_DIR = "/services/learn/log"
LOG_FILE = os.path.join(LOG_DIR, "learning.log")
PATTERNS_FILE = os.path.join("/services/learn/config", "patterns.json")

def log_message(message):
    with open(LOG_FILE, "a") as f:
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        f.write(f"[{timestamp}] {message}\n")

def get_running_containers():
    try:
        result = subprocess.run(["docker", "ps", "--format", "{{.Names}}"], 
                               capture_output=True, text=True, check=True)
        return result.stdout.strip().split('\n') if result.stdout.strip() else []
    except Exception as e:
        log_message(f"Error getting containers: {str(e)}")
        return []

def get_network_connections():
    try:
        result = subprocess.run(["netstat", "-tuln"], 
                               capture_output=True, text=True, check=True)
        return result.stdout.strip().split('\n') if result.stdout.strip() else []
    except Exception as e:
        log_message(f"Error getting network connections: {str(e)}")
        return []

def get_system_processes():
    try:
        result = subprocess.run(["ps", "aux"], 
                               capture_output=True, text=True, check=True)
        return result.stdout.strip().split('\n') if result.stdout.strip() else []
    except Exception as e:
        log_message(f"Error getting processes: {str(e)}")
        return []

def save_patterns(patterns):
    try:
        with open(PATTERNS_FILE, 'w') as f:
            json.dump(patterns, f, indent=2)
    except Exception as e:
        log_message(f"Error saving patterns: {str(e)}")

def load_patterns():
    if not os.path.exists(PATTERNS_FILE):
        return {"containers": [], "network": [], "processes": []}
    
    try:
        with open(PATTERNS_FILE, 'r') as f:
            return json.load(f)
    except Exception as e:
        log_message(f"Error loading patterns: {str(e)}")
        return {"containers": [], "network": [], "processes": []}

def learn_patterns():
    containers = get_running_containers()
    network = get_network_connections()
    processes = get_system_processes()
    
    patterns = load_patterns()
    
    # First time initialization
    if not patterns["containers"]:
        patterns["containers"] = containers
        log_message("Initial container pattern recorded")
    
    if not patterns["network"]:
        patterns["network"] = network
        log_message("Initial network pattern recorded")
    
    if not patterns["processes"]:
        # Store just process names to avoid too much data
        proc_names = [p.split()[10] if len(p.split()) > 10 else "" for p in processes]
        proc_names = [p for p in proc_names if p]
        patterns["processes"] = proc_names
        log_message("Initial process pattern recorded")
    
    # Check for new patterns
    new_containers = [c for c in containers if c not in patterns["containers"]]
    if new_containers:
        log_message(f"New containers detected: {new_containers}")
        patterns["containers"].extend(new_containers)
    
    # For network and processes, just log differences but don't update patterns
    # to avoid pattern drift
    new_listeners = []
    for conn in network:
        if "LISTEN" in conn and not any(conn in n for n in patterns["network"]):
            new_listeners.append(conn)
    
    if new_listeners:
        log_message(f"New network listeners detected: {new_listeners}")
    
    save_patterns(patterns)
    return patterns

def main():
    log_message("Adaptive learning engine started")
    os.makedirs(LOG_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(PATTERNS_FILE), exist_ok=True)
    
    cycles = 0
    while True:
        try:
            cycles += 1
            log_message(f"Performing learning cycle #{cycles}")
            patterns = learn_patterns()
            
            # Every 24 cycles (approx 1 day), do a deeper analysis
            if cycles % 24 == 0:
                log_message("Performing deep analysis")
                # Future: Add more sophisticated pattern analysis here
            
            time.sleep(3600)  # Sleep for 1 hour
        except Exception as e:
            log_message(f"Error in learning cycle: {str(e)}")
            time.sleep(300)  # Sleep for 5 minutes on error

if __name__ == "__main__":
    os.makedirs(LOG_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(PATTERNS_FILE), exist_ok=True)
    log_message("Initializing adaptive learning engine")
    main()
LEARNING
chmod +x /services/learn/bin/adaptive-learning.py
echo "  [+] Created adaptive learning script"

# Create verify script
cat > /services/verify/bin/verify.sh << 'VERIFY'
#!/bin/bash
# Daily system verification script
LOG_FILE="/services/verify/log/verify-$(date +%Y%m%d).log"

function log_message() {
  echo "[$(date)] $1" >> $LOG_FILE
}

log_message "Starting daily verification"

# Check namespace integrity
for ns in /auth /net /git /services /projects /emv /utils; do
  if [ ! -d "$ns" ]; then
    log_message "ERROR: Namespace $ns is missing"
  else
    log_message "Namespace $ns verified"
  fi
done

# Check symlinks
for link in /devlinks/*; do
  if [ ! -L "$link" ]; then
    log_message "ERROR: Symlink $link is broken or missing"
  else
    log_message "Symlink $link verified"
  fi
done

# Check Docker security configuration
if [ ! -f "/etc/docker/daemon.json" ]; then
  log_message "ERROR: Docker security configuration missing"
else
  log_message "Docker security configuration verified"
fi

# Check Falco security
if ! docker ps | grep -q falco; then
  log_message "ERROR: Falco security container not running"
else
  log_message "Falco security container verified"
fi

# Check services
for service in device-auth-engine device-auth-learn device-auth-verify.timer; do
  if ! systemctl is-enabled $service >/dev/null 2>&1; then
    log_message "ERROR: Service $service not enabled"
  else
    log_message "Service $service verified"
  fi
done

# Check for suspicious files in tmp directories
find /auth/tmp /net/tmp /git/tmp /services/*/tmp /projects/tmp /emv/tmp /utils/tmp -type f -mtime -1 2>/dev/null | while read file; do
  log_message "NOTICE: Recent file found in tmp directory: $file"
done

# Check system integrity
if command -v debsums >/dev/null 2>&1; then
  debsums_out=$(debsums -c 2>&1 | grep -v OK)
  if [ -n "$debsums_out" ]; then
    log_message "WARNING: System file integrity issues detected:"
    log_message "$debsums_out"
  else
    log_message "System file integrity verified"
  fi
fi

# Check disk usage
disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$disk_usage" -gt 90 ]; then
  log_message "WARNING: Disk usage is critical: ${disk_usage}%"
else
  log_message "Disk usage is acceptable: ${disk_usage}%"
fi

log_message "Verification completed"
VERIFY
chmod +x /services/verify/bin/verify.sh
echo "  [+] Created verification script"

# Install systemd services
cat > "$SERVICE_DIR/device-auth-engine.service" << 'EOF'
[Unit]
Description=Device Authorization Engine
After=network.target docker.service

[Service]
Type=simple
ExecStart=/services/self-heal/bin/self-healing-engine.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

cat > "$SERVICE_DIR/device-auth-learn.service" << 'EOF'
[Unit]
Description=Device Learning Engine
After=network.target

[Service]
Type=simple
ExecStart=/services/learn/bin/adaptive-learning.py
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

cat > "$SERVICE_DIR/device-auth-verify.timer" << 'EOF'
[Unit]
Description=Daily Verification Timer

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

cat > "$SERVICE_DIR/device-auth-verify.service" << 'EOF'
[Unit]
Description=Daily Device Verification

[Service]
ExecStart=/services/verify/bin/verify.sh
EOF

### PART 6: SECURITY UTILITY SCRIPTS ###
echo "[INSTALL] Creating security utility scripts..."

# Create security dashboard script
cat > $BIN_DIR/security-dashboard.sh << 'DASHBOARD'
#!/bin/bash
# Interactive security dashboard for Chrome OS

ALERT_LOG="$HOME/security-alerts.log"
SECURITY_REPORT="$HOME/security-report.txt"

display_dashboard() {
  clear
  echo -e "\e[1m\e[34m===== CHROME OS SECURITY DASHBOARD =====\e[0m"
  echo ""
  
  # Falco Status
  echo -e "\e[1m--- FALCO STATUS ---\e[0m"
  if sudo docker ps | grep -q falco; then
    echo -e "✅ Falco is running \e[32m(Docker container)\e[0m"
  else
    echo -e "❌ Falco is \e[31mNOT running\e[0m"
  fi

  # Recent Alerts
  echo ""
  echo -e "\e[1m--- RECENT SECURITY ALERTS ---\e[0m"
  if [ -f "$ALERT_LOG" ] && [ -s "$ALERT_LOG" ]; then
    tail -5 "$ALERT_LOG"
  else
    echo "No alerts logged yet."
  fi

  # Docker Status
  echo ""
  echo -e "\e[1m--- DOCKER CONTAINER STATUS ---\e[0m"
  sudo docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}"
  
  # System Resource Usage
  echo ""
  echo -e "\e[1m--- SYSTEM RESOURCE USAGE ---\e[0m"
  top -b -n 1 | head -10
  
  # Bootstrap Status
  echo ""
  echo -e "\e[1m--- BOOTSTRAP NAMESPACE STATUS ---\e[0m"
  for ns in /auth /net /git /services /projects /emv /utils; do
    if [ -d "$ns" ]; then
      echo -e "✅ $ns"
    else
      echo -e "❌ $ns missing"
    fi
  done
  
  echo ""
  echo -e "\e[1m--- MENU ---\e[0m"
  echo "1) Run security check scan"
  echo "2) View full alert log"
  echo "3) Restart Falco"
  echo "4) Check Docker security"
  echo "5) View system services status"
  echo "6) Run system self-test"
  echo "7) Exit"
  echo ""
  read -p "Enter option (1-7): " option
  
  case $option in
    1) run_security_check;;
    2) view_alert_log;;
    3) restart_falco;;
    4) check_docker_security;;
    5) view_service_status;;
    6) run_self_test;;
    7) exit 0;;
    *) display_dashboard;;
  esac
}

run_security_check() {
  clear
  echo "Running security check... Please wait."
  sudo /services/verify/bin/verify.sh
  echo "Security check completed. Report saved to /services/verify/log/"
  echo ""
  sudo tail -30 /services/verify/log/verify-$(date +%Y%m%d).log
  echo ""
  read -p "Press Enter to continue..." dummy
  display_dashboard
}

view_alert_log() {
  clear
  echo -e "\e[1m--- FULL SECURITY ALERT LOG ---\e[0m"
  if [ -f "$ALERT_LOG" ] && [ -s "$ALERT_LOG" ]; then
    less "$ALERT_LOG"
  else
    echo "No alerts logged yet."
    read -p "Press Enter to continue..." dummy
  fi
  display_dashboard
}

restart_falco() {
  clear
  echo "Restarting Falco..."
  sudo docker restart falco || sudo docker run -d --name falco --restart always --privileged \
    -v /var/run/docker.sock:/host/var/run/docker.sock \
    -v /dev:/host/dev -v /proc:/host/proc:ro -v /boot:/host/boot:ro \
    -v /lib/modules:/host/lib/modules:ro -v /usr:/host/usr:ro \
    -v /etc/falco/rules.d:/etc/falco/rules.d:ro \
    falcosecurity/falco:latest
  echo "Done!"
  read -p "Press Enter to continue..." dummy
  display_dashboard
}

check_docker_security() {
  clear
  echo "Running Docker security check..."
  cd ~/docker-bench-security 2>/dev/null || \
    git clone https://github.com/docker/docker-bench-security.git ~/docker-bench-security && \
    cd ~/docker-bench-security
  sudo sh docker-bench-security.sh
  read -p "Press Enter to continue..." dummy
  display_dashboard
}

view_service_status() {
  clear
  echo -e "\e[1m--- SYSTEM SERVICES STATUS ---\e[0m"
  for service in device-auth-engine device-auth-learn; do
    echo -e "\e[1m$service:\e[0m"
    sudo systemctl status $service --no-pager
    echo ""
  done
  read -p "Press Enter to continue..." dummy
  display_dashboard
}

run_self_test() {
  clear
  echo -e "\e[1m--- RUNNING SYSTEM SELF-TEST ---\e[0m"
  echo ""
  
  # Check directories
  echo "Checking namespaces..."
  for ns in /auth /net /git /services /projects /emv /utils; do
    if [ -d "$ns" ]; then
      echo -e "✅ $ns exists"
    else
      echo -e "❌ $ns missing"
    fi
  done
  
  # Check services
  echo -e "\nChecking services..."
  for service in device-auth-engine device-auth-learn; do
    if systemctl is-active --quiet $service; then
      echo -e "✅ $service is running"
    else
      echo -e "❌ $service is not running"
    fi
  done
  
  # Check Falco
  echo -e "\nChecking Falco..."
  if docker ps | grep -q falco; then
    echo -e "✅ Falco container is running"
  else
    echo -e "❌ Falco container is not running"
  fi
  
  # Check utilities
  echo -e "\nChecking utilities..."
  if [ -d "/utils/bin" ] && [ "$(ls -A /utils/bin 2>/dev/null)" ]; then
    echo -e "✅ Utilities are installed"
  else
    echo -e "❌ Utilities are missing"
  fi
  
  echo ""
  read -p "Press Enter to continue..." dummy
  display_dashboard
}

# Start the dashboard
display_dashboard
DASHBOARD
chmod +x $BIN_DIR/security-dashboard.sh
echo "  [+] Created security dashboard script"

# Create falco control script
cat > $BIN_DIR/falco-control.sh << 'FALCOCONTROL'
#!/bin/bash
# Script to control Falco operations

function start_falco() {
  echo "Starting Falco..."
  sudo docker start falco || sudo docker run -d --name falco \
    --restart always \
    --privileged \
    -v /var/run/docker.sock:/host/var/run/docker.sock \
    -v /dev:/host/dev \
    -v /proc:/host/proc:ro \
    -v /boot:/host/boot:ro \
    -v /lib/modules:/host/lib/modules:ro \
    -v /usr:/host/usr:ro \
    -v /etc/falco/rules.d:/etc/falco/rules.d:ro \
    falcosecurity/falco:latest
}

function stop_falco() {
  echo "Stopping Falco..."
  sudo docker stop falco
}

function restart_falco() {
  stop_falco
  sleep 2
  start_falco
}

function status_falco() {
  if sudo docker ps | grep -q falco; then
    echo "✅ Falco is running as a Docker container"
    sudo docker logs --tail 10 falco
  else
    echo "❌ Falco is not running"
  fi
}

case "$1" in
  start)
    start_falco
    ;;
  stop)
    stop_falco
    ;;
  restart)
    restart_falco
    ;;
  status)
    status_falco
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
exit 0
FALCOCONTROL
chmod +x $BIN_DIR/falco-control.sh
echo "  [+] Created Falco control script"

# Create alert script
cat > $BIN_DIR/falco-alert.sh << 'ALERTSCRIPT'
#!/bin/bash
# Script to monitor Falco logs from Docker container

ALERT_LOG="$HOME/security-alerts.log"
DOCKER_CONTAINER="falco"

touch $ALERT_LOG
echo "Starting alert monitoring from Docker container..."
sudo docker logs -f $DOCKER_CONTAINER 2>&1 | while read line; do
  if echo "$line" | grep -qi "warning\|error\|critical"; then
    echo "[$(date)] $line" >> $ALERT_LOG
    echo -e "\e[31m[ALERT]\e[0m $line"
  fi
done
ALERTSCRIPT
chmod +x $BIN_DIR/falco-alert.sh
echo "  [+] Created alert monitoring script"

### PART 7: UTILITY TOOLS INSTALLATION ###
echo "[INSTALL] Setting up utility tools namespace..."

# Create utils namespace structure
mkdir -p /utils/config /utils/bin /utils/dev /utils/net /utils/sys /utils/text /utils/scripts
ln -sfn /utils "$LINK_HUB/utils"

# Create a manifest of installed utilities
touch /utils/config/manifest.txt

# Function to install and register a utility
install_utility() {
  local utility=$1
  local category=$2
  local description=$3
  
  echo "  [+] Installing: $utility ($category)"
  apt-get install -y $utility >/dev/null 2>&1
  
  # Register in manifest
  echo "$utility|$category|$description" >> /utils/config/manifest.txt
  
  # Create symlinks based on category
  if [ -f "/usr/bin/$utility" ]; then
    ln -sf "/usr/bin/$utility" "/utils/$category/$utility"
    ln -sf "/usr/bin/$utility" "/utils/bin/$utility"
  elif [ -f "/bin/$utility" ]; then
    ln -sf "/bin/$utility" "/utils/$category/$utility"
    ln -sf "/bin/$utility" "/utils/bin/$utility"
  elif [ -f "/usr/local/bin/$utility" ]; then
    ln -sf "/usr/local/bin/$utility" "/utils/$category/$utility"
    ln -sf "/usr/local/bin/$utility" "/utils/bin/$utility"
  fi
}

echo "  [+] Installing development tools..."
install_utility "build-essential" "dev" "Compiler and build tools"
install_utility "cmake" "dev" "Cross-platform build system"
install_utility "autoconf" "dev" "Automatic configuration script builder"
install_utility "pkg-config" "dev" "Manage compile and link flags"
install_utility "git" "dev" "Distributed version control"
install_utility "go" "dev" "Go programming language"
install_utility "ruby" "dev" "Ruby programming language"
install_utility "python3" "dev" "Python programming language"
install_utility "python3-pip" "dev" "Python package manager"
install_utility "python3-venv" "dev" "Python virtual environments"

echo "  [+] Installing text processing tools..."
install_utility "nano" "text" "Simple text editor"
install_utility "pandoc" "text" "Universal document converter"
install_utility "texlive-base" "text" "LaTeX document preparation"
install_utility "jq" "text" "Command-line JSON processor"
install_utility "xmlstarlet" "text" "XML command line utilities"
install_utility "highlight" "text" "Universal source code highlighter"
install_utility "enscript" "text" "Convert text to PostScript"
install_utility "groff" "text" "Document formatting system"

echo "  [+] Installing file management tools..."
install_utility "rsync" "sys" "Fast file copying tool"
install_utility "zip" "sys" "Compression utility"
install_utility "unzip" "sys" "Extraction utility"
install_utility "p7zip-full" "sys" "7z compression utility"
install_utility "tar" "sys" "Archiving utility"
install_utility "fzf" "sys" "Command-line fuzzy finder"
install_utility "ripgrep" "sys" "Fast file content searcher"
install_utility "fd-find" "sys" "Simple, fast file finder"
install_utility "ranger" "sys" "Console file manager"
install_utility "tree" "sys" "Display directory tree structure"
install_utility "ncdu" "sys" "Disk usage analyzer"
install_utility "duf" "sys" "Disk usage utility"

echo "  [+] Installing system utilities..."
install_utility "htop" "sys" "Interactive process viewer"
install_utility "glances" "sys" "System monitoring tool"
install_utility "bpytop" "sys" "Resource monitor"
install_utility "sysstat" "sys" "System performance tools"
install_utility "lsof" "sys" "List open files"
install_utility "procps" "sys" "Process information utilities"
install_utility "psmisc" "sys" "Utilities for process management"
install_utility "strace" "sys" "System call tracer"
install_utility "tmux" "sys" "Terminal multiplexer"
install_utility "screen" "sys" "Terminal window manager"
install_utility "parallel" "sys" "Shell tool for parallel commands"
install_utility "expect" "sys" "Automate interactive applications"
install_utility "debsums" "sys" "Verify installed packages"
install_utility "apt-file" "sys" "Search for files in packages"

echo "  [+] Installing network utilities..."
install_utility "curl" "net" "URL retrieval utility"
install_utility "wget" "net" "Non-interactive downloader"
install_utility "netcat-openbsd" "net" "TCP/IP swiss army knife"
install_utility "nmap" "net" "Network exploration tool"
install_utility "tcpdump" "net" "Network packet analyzer"
install_utility "mtr" "net" "Network diagnostic tool"
install_utility "net-tools" "net" "Network utilities (ifconfig, netstat, etc)"
install_utility "iproute2" "net" "IP routing utilities"
install_utility "iftop" "net" "Network bandwidth monitor"
install_utility "whois" "net" "Client for whois directory service"
install_utility "openssh-client" "net" "Secure shell client"
install_utility "dnsutils" "net" "DNS utilities"

# Create custom utility scripts
echo "  [+] Creating utility scripts..."

# System update script
cat > /utils/scripts/update-system.sh << 'UPDATESCRIPT'
#!/bin/bash
# Update all system packages and utilities

echo "===== SYSTEM UPDATE ====="
echo "Updating apt packages..."
sudo apt-get update
sudo apt-get upgrade -y

echo "Updating Docker images..."
docker images | grep -v REPOSITORY | awk '{print $1":"$2}' | xargs -L1 docker pull

echo "Updating pip packages..."
pip3 list --outdated --format=freeze | grep -v '^\-e' | cut -d = -f 1 | xargs -n1 pip3 install -U

echo "===== UPDATE COMPLETE ====="
UPDATESCRIPT
chmod +x /utils/scripts/update-system.sh

# Network check script
cat > /utils/scripts/check-network.sh << 'NETCHECK'
#!/bin/bash
# Check network connectivity and performance

echo "===== NETWORK CHECK ====="
echo "Internet connectivity:"
ping -c 3 8.8.8.8

echo -e "\nDNS resolution:"
nslookup google.com

echo -e "\nRoute tracing:"
mtr --report --report-cycles=1 google.com

echo -e "\nOpen network connections:"
netstat -tuln | grep LISTEN

echo "===== CHECK COMPLETE ====="
NETCHECK
chmod +x /utils/scripts/check-network.sh

# System info script
cat > /utils/scripts/system-info.sh << 'SYSINFO'
#!/bin/bash
# Display comprehensive system information

echo "===== SYSTEM INFORMATION ====="
echo -e "\n== Hardware Info =="
echo "CPU:"
lscpu | grep "Model name" | cut -d: -f2- | sed 's/^[ \t]*//'
echo "Memory:"
free -h | grep Mem | awk '{print $2 " total, " $7 " available"}'
echo "Disk:"
df -h / | grep -v Filesystem | awk '{print $2 " total, " $4 " available"}'

echo -e "\n== OS Info =="
echo "Distribution:"
lsb_release -d | cut -d: -f2- | sed 's/^[ \t]*//'
echo "Kernel:"
uname -r

echo -e "\n== Network Info =="
echo "Hostname:"
hostname
echo "IP Addresses:"
ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}'

echo -e "\n== Docker Info =="
echo "Docker version:"
docker --version
echo "Running containers:"
docker ps --format "{{.Names}}" | wc -l

echo "===== INFORMATION COMPLETE ====="
SYSINFO
chmod +x /utils/scripts/system-info.sh

# Generate script to find large files
cat > /utils/scripts/find-large-files.sh << 'FINDLARGE'
#!/bin/bash
# Find large files on the system

if [ "$1" == "" ]; then
  SIZE="100M"
else
  SIZE=$1
fi

echo "Finding files larger than $SIZE..."
find / -type f -size +$SIZE -exec ls -lh {} \; 2>/dev/null | sort -k5 -h

echo "Done!"
FINDLARGE
chmod +x /utils/scripts/find-large-files.sh

# Security scan script
cat > /utils/scripts/security-scan.sh << 'SECURITYSCAN'
#!/bin/bash
# Perform a comprehensive security scan

echo "===== COMPREHENSIVE SECURITY SCAN ====="
REPORT_FILE="/tmp/security-scan-$(date +%Y%m%d).txt"
echo "Scan started at $(date)" > $REPORT_FILE

echo "Checking for unauthorized SUID files..."
echo -e "\n=== SUID FILES ===" >> $REPORT_FILE
find / -type f -perm -4000 2>/dev/null | grep -v -e "^/bin/" -e "^/sbin/" -e "^/usr/bin/" -e "^/usr/sbin/" >> $REPORT_FILE

echo "Checking for open ports..."
echo -e "\n=== OPEN PORTS ===" >> $REPORT_FILE
netstat -tuln | grep LISTEN >> $REPORT_FILE

echo "Checking for suspicious processes..."
echo -e "\n=== PROCESSES ===" >> $REPORT_FILE
ps aux | grep -v "root\|$(whoami)\|nobody\|systemd\|dbus" | grep -v "ps aux\|grep" >> $REPORT_FILE

echo "Checking Docker container security..."
echo -e "\n=== DOCKER CONTAINERS ===" >> $REPORT_FILE
docker ps -a >> $REPORT_FILE

echo "Checking for recently modified files..."
echo -e "\n=== RECENTLY MODIFIED FILES ===" >> $REPORT_FILE
find /etc /bin /sbin /usr/bin /usr/sbin -type f -mtime -2 2>/dev/null >> $REPORT_FILE

echo "Scan completed at $(date)" >> $REPORT_FILE
echo "Report saved to $REPORT_FILE"
SECURITYSCAN
chmod +x /utils/scripts/security-scan.sh

# Create utility path script
cat > /etc/profile.d/utils-path.sh << 'UTILPATH'
# Add utils directories to PATH
export PATH="$PATH:/utils/bin:/utils/scripts"
UTILPATH
chmod +x /etc/profile.d/utils-path.sh

# Create utility launcher script
cat > $BIN_DIR/utils.sh << 'UTILLAUNCHER'
#!/bin/bash
# Interactive utility tools launcher

display_menu() {
  clear
  echo -e "\e[1m\e[34m===== UTILITY TOOLS LAUNCHER =====\e[0m"
  echo ""
  
  echo -e "\e[1m--- CATEGORIES ---\e[0m"
  echo "1) Development Tools"
  echo "2) Text Processing Tools"
  echo "3) System Utilities"
  echo "4) Network Utilities"
  echo "5) Custom Scripts"
  echo "6) Show All Utilities"
  echo "7) Exit"
  echo ""
  read -p "Select a category (1-7): " category
  
  case $category in
    1) show_category "dev";;
    2) show_category "text";;
    3) show_category "sys";;
    4) show_category "net";;
    5) show_scripts;;
    6) show_all;;
    7) exit 0;;
    *) display_menu;;
  esac
}

show_category() {
  clear
  local category=$1
  echo -e "\e[1m\e[34m===== $category UTILITIES =====\e[0m"
  echo ""
  
  # Get utilities in this category
  if [ -d "/utils/$category" ]; then
    local tools=()
    local i=1
    
    while IFS= read -r tool; do
      echo "$i) $(basename $tool)"
      tools+=("$tool")
      ((i++))
    done < <(find /utils/$category -type l -o -type f -executable | sort)
    
    echo "$i) Back to main menu"
    echo ""
    
    read -p "Select a utility to run (1-$i): " selection
    
    if [ "$selection" -eq "$i" ]; then
      display_menu
    elif [ "$selection" -ge 1 ] && [ "$selection" -lt "$i" ]; then
      clear
      echo "Running $(basename ${tools[$selection-1]})..."
      ${tools[$selection-1]}
      echo ""
      read -p "Press Enter to continue..." dummy
      show_category "$category"
    else
      show_category "$category"
    fi
  else
    echo "Category not found!"
    read -p "Press Enter to continue..." dummy
    display_menu
  fi
}

show_scripts() {
  clear
  echo -e "\e[1m\e[34m===== CUSTOM SCRIPTS =====\e[0m"
  echo ""
  
  # Get all scripts
  local scripts=()
  local i=1
  
  while IFS= read -r script; do
    echo "$i) $(basename $script)"
    scripts+=("$script")
    ((i++))
  done < <(find /utils/scripts -type f -executable | sort)
  
  echo "$i) Back to main menu"
  echo ""
  
  read -p "Select a script to run (1-$i): " selection
  
  if [ "$selection" -eq "$i" ]; then
    display_menu
  elif [ "$selection" -ge 1 ] && [ "$selection" -lt "$i" ]; then
    clear
    echo "Running $(basename ${scripts[$selection-1]})..."
    ${scripts[$selection-1]}
    echo ""
    read -p "Press Enter to continue..." dummy
    show_scripts
  else
    show_scripts
  fi
}

show_all() {
  clear
  echo -e "\e[1m\e[34m===== ALL UTILITIES =====\e[0m"
  echo ""
  
  if [ -f "/utils/config/manifest.txt" ]; then
    echo -e "NAME\t\tCATEGORY\tDESCRIPTION"
    echo -e "----\t\t--------\t-----------"
    cat /utils/config/manifest.txt | while IFS="|" read -r name category desc; do
      printf "%-15s %-15s %s\n" "$name" "$category" "$desc"
    done
  else
    echo "Manifest file not found!"
  fi
  
  echo ""
  read -p "Press Enter to continue..." dummy
  display_menu
}

# Start the launcher
display_menu
UTILLAUNCHER
chmod +x $BIN_DIR/utils.sh

# Add Python security modules
echo "  [+] Installing Python security modules..."
pip3 install --upgrade pip
pip3 install requests cryptography paramiko pyOpenSSL pycryptodome

echo "[UTILS] Utility tools installation complete."

### PART 8: ALIASES AND NAVIGATION HELPERS ###
echo "[INSTALL] Creating navigation aliases and shortcuts..."

# Create aliases file
cat > /etc/profile.d/custom-aliases.sh << 'ALIASES'
#!/bin/bash
# Custom aliases for easier navigation and usage

# Directory navigation
alias cdauth='cd /auth'
alias cdnet='cd /net'
alias cdgit='cd /git'
alias cdserv='cd /services'
alias cdproj='cd /projects'
alias cdemv='cd /emv'
alias cdutils='cd /utils'
alias cdlinks='cd /devlinks'

# Service navigation
alias cdverify='cd /services/verify'
alias cdlearn='cd /services/learn'
alias cdheal='cd /services/self-heal'

# Utility shortcuts
alias ut='utils.sh'                     # Launch utility menu
alias updatesys='/utils/scripts/update-system.sh'  # Update system
alias netcheck='/utils/scripts/check-network.sh'   # Check network
alias sysinfo='/utils/scripts/system-info.sh'      # Show system info
alias bigfiles='/utils/scripts/find-large-files.sh' # Find large files
alias secscan='/utils/scripts/security-scan.sh'    # Run security scan

# Docker shortcuts
alias dps='docker ps'                   # List containers
alias dls='docker images'               # List images
alias dlog='docker logs'                # Show container logs
alias dex='docker exec -it'             # Execute in container
alias drm='docker rm'                   # Remove container
alias drmi='docker rmi'                 # Remove image

# Security shortcuts
alias secdash='security-dashboard.sh'   # Launch security dashboard
alias falcostatus='falco-control.sh status'  # Check Falco status
alias falcorestart='falco-control.sh restart' # Restart Falco
alias dockersec='cd ~/docker-bench-security && sudo sh docker-bench-security.sh' # Run Docker security check

# File management
alias ll='ls -alF'                      # Detailed list
alias la='ls -A'                        # Show hidden files
alias lt='ls -ltr'                      # List sorted by time
alias lsize='ls -lSrh'                  # List sorted by size
alias findinfiles='grep -r'             # Find text in files

# Process management
alias psa='ps aux'                      # Show all processes
alias psg='ps aux | grep'               # Search processes
alias topme='top -u $(whoami)'          # Top for current user

# System utilities
alias dfh='df -h'                       # Disk usage human readable
alias duh='du -h --max-depth=1'         # Directory size
alias meminfo='free -h'                 # Memory information
alias cpuinfo='lscpu'                   # CPU information
alias myip='curl -s ifconfig.me'        # Show public IP
alias localip='hostname -I'             # Show local IP

# Namespace quick access
alias authbin='cd /auth/bin'
alias authconfig='cd /auth/config'
alias netbin='cd /net/bin'
alias netconfig='cd /net/config'
alias gitbin='cd /git/bin'
alias gitconfig='cd /git/config'
alias utilbin='cd /utils/bin'
alias utilconfig='cd /utils/config'

# Logs quick access
alias authlogs='cd /auth/log'
alias netlogs='cd /net/log'
alias gitlogs='cd /git/log'
alias servlogs='cd /services/verify/log'
alias healogs='cd /services/self-heal/log'
alias learnlogs='cd /services/learn/log'
alias falcologs='sudo docker logs falco'

# Quick edit configurations
alias editdocker='sudo nano /etc/docker/daemon.json'
alias editfalco='sudo nano /etc/falco/falco.yaml'

# Navigation helpers
alias nav='navigate.sh'                 # Launch navigation menu
alias help='help.sh'                    # Show help for commands

# Enhanced ls with color
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Safety nets
alias rm='rm -i'                        # Confirm before removing
alias cp='cp -i'                        # Confirm before overwriting
alias mv='mv -i'                        # Confirm before overwriting

# Quick service management
alias restart-auth='sudo systemctl restart device-auth-engine.service'
alias restart-learn='sudo systemctl restart device-auth-learn.service'

# Function to quickly search utility tools
function findtool() {
    grep -i "$1" /utils/config/manifest.txt
}

# Function to quickly check services status
function checkservices() {
    echo "===== SERVICES STATUS ====="
    systemctl status device-auth-engine.service --no-pager
    echo "------------------------"
    systemctl status device-auth-learn.service --no-pager
    echo "------------------------"
    systemctl status device-auth-verify.timer --no-pager
    echo "------------------------"
    docker ps | grep falco || echo "Falco container not running!"
}

# Function to find files in the namespace structure
function findfile() {
    find /auth /net /git /services /projects /emv /utils -name "*$1*" 2>/dev/null
}

# Function to quickly access any namespace directory
function goto() {
    case "$1" in
        auth|net|git|services|projects|emv|utils|devlinks)
            cd "/$1"
            ;;
        verify|learn|heal)
            cd "/services/$1"
            ;;
        *)
            echo "Unknown namespace: $1"
            echo "Available namespaces: auth, net, git, services, projects, emv, utils, devlinks"
            echo "Available service directories: verify, learn, heal"
            ;;
    esac
}
ALIASES
chmod +x /etc/profile.d/custom-aliases.sh

# Create .bashrc enhancement for user
user_home="/home/$(logname)"
if [ -f "$user_home/.bashrc" ]; then
  cat >> "$user_home/.bashrc" << 'BASHRC'

# Load custom aliases
if [ -f /etc/profile.d/custom-aliases.sh ]; then
    . /etc/profile.d/custom-aliases.sh
fi

# Enhanced prompt with current namespace indication
function prompt_command {
    # Get the current directory
    local pwd=$(pwd)
    
    # Check if we're in a known namespace
    local namespace=""
    for ns in auth net git services projects emv utils devlinks; do
        if [[ $pwd == "/$ns"* ]]; then
            namespace="[$ns] "
            break
        fi
    done
    
    # Set a colored prompt with namespace information
    PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\] \[\033[01;31m\]$namespace\[\033[00m\]$ "
}
PROMPT_COMMAND=prompt_command

# Helpful welcome message
echo "Welcome to your secure Chrome OS environment!"
echo "Quick navigation commands:"
echo "  goto <namespace>   - Jump to namespace (auth, net, git, etc.)"
echo "  ut                 - Launch utility tools menu"
echo "  secdash            - Launch security dashboard"
echo "  checkservices      - Check status of all services"
echo "Type 'alias' to see all available shortcuts"
BASHRC

  echo "  [+] Added custom aliases to .bashrc"
fi

# Create tab completion for custom functions
cat > /etc/bash_completion.d/custom_completion << 'COMPLETION'
# Tab completion for goto function
_goto_complete()
{
  local cur=${COMP_WORDS[COMP_CWORD]}
  local namespaces="auth net git services projects emv utils devlinks verify learn heal"
  
  COMPREPLY=( $(compgen -W "$namespaces" -- $cur) )
  return 0
}
complete -F _goto_complete goto

# Tab completion for Docker containers
_docker_container_complete()
{
  local cur=${COMP_WORDS[COMP_CWORD]}
  local containers=$(docker ps --format "{{.Names}}")
  
  COMPREPLY=( $(compgen -W "$containers" -- $cur) )
  return 0
}
complete -F _docker_container_complete dlog
complete -F _docker_container_complete dex
complete -F _docker_container_complete drm
COMPLETION

echo "[ALIASES] Navigation aliases and shortcuts created."

# Create quick navigation menu
cat > $BIN_DIR/navigate.sh << 'NAVMENU'
#!/bin/bash
# Quick navigation menu for namespace structure

# Display the menu
display_menu() {
  clear
  echo -e "\e[1m\e[34m===== NAMESPACE NAVIGATION =====\e[0m"
  echo ""
  
  echo -e "\e[1m--- ROOT NAMESPACES ---\e[0m"
  echo "1) /auth        - Authentication & authorization"
  echo "2) /net         - Network components"
  echo "3) /git         - Version control"
  echo "4) /services    - System services"
  echo "5) /projects    - Project templates"
  echo "6) /emv         - EMV configuration"
  echo "7) /utils       - Utility tools"
  echo ""
  
  echo -e "\e[1m--- SERVICE DIRECTORIES ---\e[0m"
  echo "8) /services/verify    - Verification services"
  echo "9) /services/learn     - Learning services"
  echo "10) /services/self-heal - Self-healing services"
  echo ""
  
  echo -e "\e[1m--- UTILITIES ---\e[0m"
  echo "11) View file structure"
  echo "12) Launch security dashboard"
  echo "13) Launch utility tools"
  echo "14) Exit"
  echo ""
  
  read -p "Enter your choice (1-14): " choice
  
  case $choice in
    1) cd /auth && exec bash;;
    2) cd /net && exec bash;;
    3) cd /git && exec bash;;
    4) cd /services && exec bash;;
    5) cd /projects && exec bash;;
    6) cd /emv && exec bash;;
    7) cd /utils && exec bash;;
    8) cd /services/verify && exec bash;;
    9) cd /services/learn && exec bash;;
    10) cd /services/self-heal && exec bash;;
    11) view_structure;;
    12) security-dashboard.sh;;
    13) utils.sh;;
    14) exit 0;;
    *) display_menu;;
  esac
}

# View directory structure
view_structure() {
  clear
  echo -e "\e[1m\e[34m===== NAMESPACE STRUCTURE =====\e[0m"
  echo ""
  
  echo "Root namespaces:"
  ls -l --color / | grep -E 'auth|net|git|services|projects|emv|utils|devlinks'
  
  echo -e "\nService directories:"
  ls -l --color /services
  
  echo -e "\nUtility categories:"
  ls -l --color /utils | grep -v "config\|bin"
  
  echo ""
  read -p "Press Enter to return to the menu..." dummy
  display_menu
}

# Start the menu
display_menu
NAVMENU
chmod +x $BIN_DIR/navigate.sh

echo "  [+] Created navigation menu script"

# Create help script to show all available commands and tools
cat > $BIN_DIR/help.sh << 'HELPSCRIPT'
#!/bin/bash
# Help script to show all available commands and tools

show_help() {
  clear
  echo -e "\e[1m\e[34m===== SECURE ENVIRONMENT HELP =====\e[0m"
  echo ""
  
  echo -e "\e[1m--- NAMESPACE STRUCTURE ---\e[0m"
  echo "/auth        - Authentication & authorization components"
  echo "/net         - Network components and configurations"
  echo "/git         - Version control and code repositories"
  echo "/services    - System services (verify, learn, self-heal)"
  echo "/projects    - Project templates and development"
  echo "/emv         - EMV configuration and components"
  echo "/utils       - Utility tools and scripts"
  echo "/devlinks    - Symlinks to all namespaces"
  echo ""
  
  echo -e "\e[1m--- MAIN COMMANDS ---\e[0m"
  echo "navigate.sh    - Interactive navigation menu"
  echo "security-dashboard.sh - Security monitoring dashboard"
  echo "utils.sh       - Utility tools menu"
  echo "falco-control.sh - Control Falco security monitoring"
  echo "help.sh        - This help screen"
  echo ""
  
  echo -e "\e[1m--- NAVIGATION SHORTCUTS ---\e[0m"
  echo "goto <namespace> - Jump directly to a namespace"
  echo "cdauth, cdnet, cdgit, etc. - Change to specific namespace"
  echo "cdverify, cdlearn, cdheal - Change to service directory"
  echo ""
  
  echo -e "\e[1m--- UTILITY SHORTCUTS ---\e[0m"
  echo "ut          - Launch utility menu"
  echo "updatesys   - Update system packages"
  echo "netcheck    - Check network connectivity"
  echo "sysinfo     - Show system information"
  echo "bigfiles    - Find large files"
  echo "secscan     - Run security scan"
  echo ""
  
  echo -e "\e[1m--- SECURITY SHORTCUTS ---\e[0m"
  echo "secdash     - Launch security dashboard"
  echo "falcostatus - Check Falco status"
  echo "falcorestart - Restart Falco"
  echo "dockersec   - Run Docker security check"
  echo ""
  
  echo -e "\e[1m--- HELPFUL FUNCTIONS ---\e[0m"
  echo "findtool <name>   - Find a utility tool by name"
  echo "findfile <name>   - Find files in namespace structure"
  echo "checkservices     - Check status of all services"
  echo ""
  
  echo "Type 'alias' to see all available aliases"
}

# Show the help
show_help

# Optional: add arguments handling
if [
"$1" == "nav" ]; then
  echo -e "\e[1m\e[33mNavigation Commands:\e[0m"
  grep "alias cd" /etc/profile.d/custom-aliases.sh | sort
  echo ""
elif [ "$1" == "util" ]; then
  echo -e "\e[1m\e[33mUtility Commands:\e[0m"
  grep -E "alias (ut|update|net|sys|big|sec)" /etc/profile.d/custom-aliases.sh | sort
  echo ""
elif [ "$1" == "docker" ]; then
  echo -e "\e[1m\e[33mDocker Commands:\e[0m"
  grep "alias d" /etc/profile.d/custom-aliases.sh | sort
  echo ""
elif [ "$1" == "security" ]; then
  echo -e "\e[1m\e[33mSecurity Commands:\e[0m"
  grep -E "alias (sec|falco|docker)" /etc/profile.d/custom-aliases.sh | sort
  echo ""
fi
HELPSCRIPT
chmod +x $BIN_DIR/help.sh

echo "  [+] Created help script"

### PART 9: ADDITIONAL SECURITY AND OPTIMIZATION ###
echo "[INSTALL] Applying additional security and Chrome OS optimizations..."

# Install Chrome OS specific performance optimizations
cat > /etc/sysctl.d/99-chromeos-optimize.conf << 'SYSCTL'
# Chrome OS performance optimizations
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
SYSCTL

# Apply the sysctl settings
sysctl -p /etc/sysctl.d/99-chromeos-optimize.conf

# Setup improved bash history
cat > /etc/profile.d/bash-history.sh << 'BASHHISTORY'
# Enhanced Bash history settings
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoreboth:erasedups
export HISTTIMEFORMAT="%F %T "
shopt -s histappend
BASHHISTORY
chmod +x /etc/profile.d/bash-history.sh

# Create a robust user-level .bashrc configuration
cat > $user_home/.bashrc.local << 'USERCONFIG'
# Local user configurations for Chrome OS environment

# Enhanced command completion
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Better navigation with pushd/popd
alias cd='pushd > /dev/null'
alias back='popd > /dev/null'
alias dirs='dirs -v'

# Automatic directory creation if not exists
function mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Extract any compressed file
function extract() {
  if [ -f $1 ] ; then
    case $1 in
      *.tar.bz2)   tar xvjf $1    ;;
      *.tar.gz)    tar xvzf $1    ;;
      *.tar.xz)    tar xvJf $1    ;;
      *.bz2)       bunzip2 $1     ;;
      *.rar)       unrar x $1     ;;
      *.gz)        gunzip $1      ;;
      *.tar)       tar xvf $1     ;;
      *.tbz2)      tar xvjf $1    ;;
      *.tgz)       tar xvzf $1    ;;
      *.zip)       unzip $1       ;;
      *.Z)         uncompress $1  ;;
      *.7z)        7z x $1        ;;
      *)           echo "'$1' cannot be extracted via extract()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

# Find/Replace in all files
function findreplace() {
  find . -type f -name "$3" -exec sed -i "s/$1/$2/g" {} \;
}

# Git shortcuts
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph'

# Chrome OS specific
function crouton_share() {
  if [ -d "/mnt/chromeos/GoogleDrive/MyDrive" ]; then
    ln -sf "/mnt/chromeos/GoogleDrive/MyDrive" "$HOME/GoogleDrive"
    echo "Google Drive linked to $HOME/GoogleDrive"
  else
    echo "Google Drive not found at expected location"
  fi
}

# Add container IP to /etc/hosts for better DNS
function fix_container_dns() {
  container_ip=$(hostname -I | awk '{print $1}')
  container_name=$(hostname)
  if ! grep -q "$container_name" /etc/hosts; then
    echo "$container_ip $container_name" | sudo tee -a /etc/hosts
    echo "Added $container_name to /etc/hosts"
  fi
}

# Integration for Chrome OS clipboard (if available)
if [ -f /usr/bin/xclip ]; then
  alias pbcopy='xclip -selection clipboard'
  alias pbpaste='xclip -selection clipboard -o'
fi
USERCONFIG

# Add the local file to .bashrc if not already included
if ! grep -q "source ~/.bashrc.local" "$user_home/.bashrc"; then
  echo -e "\n# Load local configuration\nif [ -f ~/.bashrc.local ]; then\n  source ~/.bashrc.local\nfi" >> "$user_home/.bashrc"
fi

# Set proper permissions on the file
chown $(logname):$(logname) "$user_home/.bashrc.local"

### PART 10: FINALIZING ###
echo "[INSTALL] Finalizing setup..."

# Set proper permissions
chown -R root:root /auth /net /git /services /projects /emv /utils /devlinks
chmod -R 755 /auth /net /git /services /projects /emv /utils

# Install Docker Bench Security
if [ ! -d "/home/$(logname)/docker-bench-security" ]; then
  git clone https://github.com/docker/docker-bench-security.git /home/$(logname)/docker-bench-security
  chown -R $(logname):$(logname) /home/$(logname)/docker-bench-security
  echo "  [+] Installed Docker Bench Security"
fi

# Reload systemd and enable services
systemctl daemon-reload
systemctl enable device-auth-engine.service
systemctl enable device-auth-learn.service
systemctl enable device-auth-verify.timer

# Start the services
systemctl start device-auth-engine.service
systemctl start device-auth-learn.service
systemctl start device-auth-verify.timer

# Add alias for easy access to the dashboard
user_home="/home/$(logname)"
if [ -f "$user_home/.bashrc" ]; then
  if ! grep -q "alias sec-dash=" "$user_home/.bashrc"; then
    echo "alias sec-dash='security-dashboard.sh'" >> "$user_home/.bashrc"
    echo "  [+] Added 'sec-dash' alias to .bashrc"
  fi
fi

# Create Chrome OS Linux container startup script
cat > $BIN_DIR/startup.sh << 'STARTUP'
#!/bin/bash
# Chrome OS Linux container startup script

# Display welcome message
echo -e "\e[1m\e[34m============================================\e[0m"
echo -e "\e[1m\e[34m   CHROME OS SECURE ENVIRONMENT STARTED    \e[0m"
echo -e "\e[1m\e[34m============================================\e[0m"
echo ""

# Check if services are running
echo "Checking services status..."
device_auth=$(systemctl is-active device-auth-engine.service)
device_learn=$(systemctl is-active device-auth-learn.service)
falco_status=$(docker ps | grep -q falco && echo "active" || echo "inactive")

# Display status
echo -e "Device Auth Engine: \e[1m\e[$([ "$device_auth" == "active" ] && echo "32" || echo "31")m$device_auth\e[0m"
echo -e "Device Learn Engine: \e[1m\e[$([ "$device_learn" == "active" ] && echo "32" || echo "31")m$device_learn\e[0m"
echo -e "Falco Security: \e[1m\e[$([ "$falco_status" == "active" ] && echo "32" || echo "31")m$falco_status\e[0m"
echo ""

# Start services if needed
if [ "$falco_status" != "active" ]; then
  echo "Starting Falco security monitoring..."
  sudo falco-control.sh start
fi

# Show available commands
echo -e "\e[1m\e[33mQuick commands:\e[0m"
echo "  nav        - Navigate namespaces"
echo "  secdash    - Open security dashboard"
echo "  ut         - Access utility tools"
echo "  help       - Show all commands"
echo ""

# Show system info
uptime=$(uptime -p)
load=$(uptime | awk -F'load average:' '{print $2}' | sed 's/,//g')
mem=$(free -h | awk '/^Mem:/ {print $3 " used of " $2 " total"}')
disk=$(df -h / | awk 'NR==2 {print $3 " used of " $2 " total (" $5 ")"}')

echo -e "\e[1m\e[33mSystem status:\e[0m"
echo "  Uptime: $uptime"
echo "  Load: $load"
echo "  Memory: $mem"
echo "  Disk: $disk"
echo ""

echo -e "\e[1m\e[34m============================================\e[0m"
STARTUP
chmod +x $BIN_DIR/startup.sh

# Add startup script to bashrc if not already added
if ! grep -q "startup.sh" "$user_home/.bashrc"; then
  echo -e "\n# Run startup script\nif [ -f $BIN_DIR/startup.sh ]; then\n  $BIN_DIR/startup.sh\nfi" >> "$user_home/.bashrc"
fi

echo "[INSTALLATION COMPLETE] System is now completely cleaned and freshly installed."
echo ""
echo "===== NEXT STEPS ====="
echo "1. Log out and log back in to apply all changes"
echo "2. The startup script will automatically run and check services"
echo "3. Use 'secdash' or 'security-dashboard.sh' to open the security dashboard"
echo "4. Use 'nav' or 'navigate.sh' to navigate between namespaces"
echo "5. Use 'ut' or 'utils.sh' to access utility tools"
echo "6. Use 'help' or 'help.sh' to see all available commands"
echo ""
echo "System has been completely reset and configured from scratch!"