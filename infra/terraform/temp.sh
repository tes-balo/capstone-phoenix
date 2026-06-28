#!/bin/bash

regions=(
  eastus
  eastus2
  centralus
  westus2
  swedencentral
  northeurope
)

sizes=(
  Standard_B1s
  Standard_B1ms
  Standard_B2s
)

for region in "${regions[@]}"; do
    echo "===== $region ====="

    for size in "${sizes[@]}"; do
        echo "---- $size ----"

        az vm create \
          --resource-group capstone-phoenix-rg \
          --name probe \
          --image Ubuntu2204 \
          --size "$size" \
          --admin-username azureuser \
          --generate-ssh-keys \
          --location "$region" \
          --validate

        echo
    done
done