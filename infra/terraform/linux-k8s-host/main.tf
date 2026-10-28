# kube-scheduler and kube-controller-manager are kubeadm static pods -
# kubelet sources their spec from /etc/kubernetes/manifests directly, not
# from the apiserver, so this is a host file edit rather than a kubectl
# change. kubelet watches that directory and restarts the static pod
# automatically once the file changes - no separate restart step needed
# here.
#
# sed's substitution is naturally idempotent (a no-op once the flag already
# reads "false"), so re-applying this is always safe.
resource "terraform_data" "disable_leader_election" {
  count = var.disable_leader_election ? 1 : 0

  triggers_replace = {
    disable_leader_election = var.disable_leader_election
  }

  connection {
    type  = "ssh"
    host  = var.ssh_host
    user  = var.ssh_user
    port  = var.ssh_port
    agent = true
  }

  provisioner "remote-exec" {
    inline = [
      "sed -i 's/--leader-elect=true/--leader-elect=false/' /etc/kubernetes/manifests/kube-scheduler.yaml",
      "sed -i 's/--leader-elect=true/--leader-elect=false/' /etc/kubernetes/manifests/kube-controller-manager.yaml",
    ]
  }
}
