# Setting up an infinigram array on a GCP disk

1. Create a disk on GCP
    - ```
    gcloud compute disks create infinigram-pileval-test \
    --project=ai2-reviz \
    --type=pd-balanced \
    --size=10GB \
    --zone=us-west1-b
    ```
2. Attach the disk to a GCP VM
3. SSH into the VM 
4. Format the disk with `parted`
    - `sudo parted /dev/sdb`
    - `mklabel loop`
    - `mkpart (start 0%, end 100%, ext4 format)`
5. Mount the disk
    - `sudo mkdir /mnt/<whatever name you want>`
    - `sudo mount /dev/sdb1 /mnt/<whatever name you want>`
    - Do whatever you need to do to download the array
6. Exit the SSH session and remove the disk from the VM

Need to figure out a way for us to easily make a k8s pod and use that to write instead