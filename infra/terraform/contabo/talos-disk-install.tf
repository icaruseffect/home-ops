wget https://factory.talos.dev/image/dc7b152cb3ea99b821fcb7340ce7168313ce393d663740b791c36f6e95fc8586/v1.8.1/nocloud-amd64.raw.xz
xz -d nocloud-amd64.raw.xz
dd status=progress if=nocloud-amd64.raw of=/dev/sda && sync
