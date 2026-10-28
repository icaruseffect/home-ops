https://cert-manager.io/docs/trust/trust-manager/installation/#3-install-trust-manager
helm upgrade trust-manager oci://quay.io/jetstack/charts/trust-manager \
--install \
--namespace cert-manager \
--wait
