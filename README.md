# AKS Cluster

## Productivity setup in VS Code in Mac
Writing `kubectl` everytime in console takes some time, so we configure to use the alias `k` to save some time:
```
# enable zsh completion (once)
autoload -Uz compinit
compinit

# kubectl completion for zsh
source <(kubectl completion zsh)

# alias: use k instead of kubectl
alias k=kubectl
# make k use the same completion as kubectl
compdef k=kubectl
```

Finally, reload your shell:
```
source ~/.zshrc
```



## Before Cluster & HelmCharts are created
### Connecting to the Azure AKS Cluster
According azure documentation we have to use this first command:
```
az account set --subscription <AZURE-SUBSCRIPTION-NUMBER>
```


### AKS Kubeconfig file:
Later, we can create a separate Kubeconfig file for this new AKS Cluster (in this example I call the Kubeconfig file `aks-dev`), in order to add some order, using:
```
az aks get-credentials -g aks-terraform-rg -n aks-terraform --file ~/.kube/aks-dev
export KUBECONFIG=~/.kube/aks-dev
kubectl config get-contexts
```

So every time you want to use this specifi kubeconfig file you have to export it in the console using `export KUBECONFIG=~/.kube/aks-dev`.

Finally, to verify you are in the right kubeconfig, check it using this command:
```
kubectl config view
```

Or also visit the local Path `/Users/<YOUR-USERNAME>/.kube` to see the kubeconfig files available.



## Executing Terraform Apply
To use terraform apply in Azure we have to mention in the terraform code the `subscription_id`, so we use before `terraform plan` this command: 
```
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo "$ARM_SUBSCRIPTION_ID"
```

### PART1: This builds the RG + cluster only.
And after this, when we want to run `terraform plan` or `terraform apply` we use the respective env. name (`dev` or `prod`), for example:
```
terraform plan 

terraform apply 
```

### PART2: Connecting to the Azure AKS Cluster, & put the new AKS context into your dedicated kubeconfig file
After the AKS Cluster is created, you can run this command in your terminal:
```
az aks get-credentials \
  --resource-group aks-terraform-rg \
  --name aks-terraform \
  --file ~/.kube/aks-dev \
  --overwrite-existing

kubectl --kubeconfig ~/.kube/aks-dev get nodes        # just as sanity check
```

### PART3: Run Terraform again with the flag to enable the NGINX INGRESS installation:
Now that the Cluster is created and the AKS context is into your dedicated kubeconfig file, install through Terraform the software:
```
terraform apply -var="install_helmcharts=true"
```
*due to a bug, you may need you apply this command twice.


Finally to destroy your provisionated infrastructure:
```
terraform destroy -var="install_helmcharts=true"
```



## Using K9S
If you wanna use K9S, you have can run the program using a custom kubeconfig (in this example I call the Kubeconfig file `aks-dev`):
```
k9s --kubeconfig ~/.kube/aks-dev
```


## ArgoCD first steps:
To access ArgoCD you have to add in your local `/etc/hosts` the IP that terraform outputs and the `host url`, it normally you will write this line in this structure: 
```
< TERRAFORM-OUTPUT-IP >   http://argocd.aks-terraform.westeurope.cloudapp.azure.com/applications

```

Once you access the ARGO CD login screen you have to run this command to get the `initial admin password`:
```
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

And for the User in the ArgoCD login page write the standard value: `admin`