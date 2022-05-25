#!/bin/bash
wget https://docs.projectcalico.org/manifests/calico.yaml
kubeadm init
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl apply -f calico.yaml
sudo kubeadm token create --print-join-command >> k8-join.sh
ssh -o StrictHostKeyChecking=no -i id_rsa azureuser@10.0.1.11 'sudo bash -s' -- < k8-join.sh
ssh -o StrictHostKeyChecking=no -i id_rsa azureuser@10.0.1.12 'sudo bash -s' -- < k8-join.sh
ssh -o StrictHostKeyChecking=no -i id_rsa azureuser@10.0.1.13 'sudo bash -s' -- < k8-join.sh