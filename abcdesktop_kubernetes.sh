
# echo 'load module overlay br_netfilter'
# 
# Enable kernel modules
# sudo modprobe overlay
# sudo modprobe br_netfilter

# Add some settings to sysctl
echo 'enable ip forwarding for routing'
sudo tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

# Reload sysctl
echo 'Reload sysctl'
sudo sysctl --system


echo 'Reconfigure docker change default cgroups to native.cgroupdriver=systemd'
# Create required directories
sudo mkdir -p /etc/systemd/system/docker.service.d

# Create daemon json config file
sudo tee /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

# Start and enable Services
echo 'Start and enable Services'
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo systemctl enable docker




# Disable swap
echo 'Disable swap'
sed -i '/swap/d' /etc/fstab
swapoff -a

# Install Kubernetes
echo 'Install Kubernetes'
apt-get update && apt-get install -y apt-transport-https ca-certificates curl
curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl


# Start kubelet
echo 'Start kubelet'
sudo systemctl enable kubelet
sudo service kubelet start

# Initialize Kubernetes
echo "Initialize Kubernetes Cluster"
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 >> /root/kubeinit.log 2>&1

sudo cat /root/kubeinit.log

# Copy Kube admin config
echo "Copy kube admin config to Vagrant user .kube directory"
mkdir -p $HOME/.kube
sudo chown vagrant:root /etc/kubernetes/admin.conf
# sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
# sudo chown vagrant:vagrant $HOME/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf

echo 'kubectl config view'
kubectl config view

echo 'kubectl cluster-info'
while ! kubectl cluster-info
do
    echo waiting 10s for kubectl cluster-info
    sleep 10
done


echo 'waiting for pods condition=Ready pod/etcd-kmaster'
kubectl -n kube-system wait pod/etcd-kmaster --for=condition=Ready --timeout=-1s
echo 'waiting for pods condition=Ready pod/kube-apiserver-kmaster'
kubectl -n kube-system wait pod/kube-apiserver-kmaster --for=condition=Ready --timeout=-1s
echo 'waiting for pods condition=Ready pod/kube-controller-manager-kmaster'
kubectl -n kube-system wait pod/kube-controller-manager-kmaster --for=condition=Ready --timeout=-1s
echo 'waiting for pods condition=Ready pod/kube-scheduler-kmaster'
kubectl -n kube-system wait pod/kube-scheduler-kmaster --for=condition=Ready --timeout=-1s

# Remove Master Node Taint
echo 'Remove Master Node Taint'
while ! kubectl taint node `hostname` node-role.kubernetes.io/master-
do
    echo waiting 10s for kubectl taint
    sleep 10
done

# Deploy flannel network
echo "Deploy flannel network"
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

echo 'waiting for node condition=Ready'
kubectl -n kube-system wait node/kmaster --for=condition=Ready --timeout=-1s

#echo "Deploy Calico network"
#kubectl create -f https://docs.projectcalico.org/v3.9/manifests/calico.yaml

# install abcdesktop.io
export TAG=dev
curl -sL https://raw.githubusercontent.com/abcdesktopio/conf/main/kubernetes/install.sh | bash

# start all newman test
echo "start newman run"
newman run -e conf/postman-collections/environment-kubernetes.json -d conf/postman-collections/ldap_provider_planet_users.json conf/postman-collections/abcdesktoplogin_explicit.postman_collection.json
# -r htmlextra --reporter-htmlextra-export /vagrant


