$driver = "TOSHIBA Universal Printer 2"
$address = "192.168.0.240"
$name = "TOSHIBA-recepce"
$sleep = "3"

Invoke-Command {pnputil.exe -a "C:\Program Files\ToshibaDRV\Driver\64bit\eSf6u.inf" }

Add-PrinterDriver -Name $driver

Start-Sleep $sleep

Add-PrinterPort -Name $address -PrinterHostAddress $address

start-sleep $sleep

Add-Printer -DriverName $driver -Name $name -PortName $address

Start-Sleep $sleep 

get-printer |Out-Printer -Name $name 