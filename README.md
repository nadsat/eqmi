# Eqmi

QMI (Qualcomm MSM Interface) client implementation in Elixir

### Example use, WDS control point

This example shows how to stablish a data connection similar to

```
qmicli --device=/dev/cdc-wdm0 --device-open-proxy --wds-start-network="ip-type=4,apn=my.isp.com" --client-no-release-cid
```

Initialization

```
iex(1)>  {:ok, dev} = Eqmi.start_link("/dev/cdc-wdm0")
{:ok, #PID<0.199.0>}
```

Create a control point for WDS

```
iex(2)> client = Eqmi.client(dev, :qmi_wds)
#Reference<0.1318031025.2560360450.258300>
```

Create start network message

```
iex(3)> msg = Eqmi.WDS.request(:start_network, [{:apn, "my.isp.com"},{:ip_family_preference, 4}])
<<32, 0, ..., 99, 108>>
```

Send message

```
iex(4)> Eqmi.send_message(dev, client, [msg])
:ok
iex(5)>flush
{:qmux,
 %{
   client_id: 20,
   message_type: :response,
   messages: [
     %{
       msg_id: 32,
       parameters: [
         %{packet_data_handle: 2688802694, param_id: 1},
         %{param_id: 2, result: %{error_code: 0, error_status: 0}}
       ]
     }
   ],
   sender_type: :service,
   service_type: :qmi_wds,
   tx_id: 1
 }}
{:qmux,
 %{
   client_id: 20,
   message_type: :indication,
   messages: [
     %{
       msg_id: 34,
       parameters: [
         %{param_id: <<20>>, value: <<5>>},
         %{param_id: <<19>>, value: <<128, 136>>},
         %{ip_family: 4, param_id: 18},
         %{
           connection_status: %{reconfiguration_required: 0, status: 2},
           param_id: 1
         }
       ]
     }
   ],
   sender_type: :service,
   service_type: :qmi_wds,
   tx_id: 1
 }}
:ok
```

and sending a dhcp request:

```
$ sudo udhcpc -q -f -n -i wwan0
udhcpc: started, v1.30.1
udhcpc: sending discover
udhcpc: sending select for 10.9.173.23
udhcpc: lease of 10.9.173.23 obtained, lease time 7200
```

to change qmi_wwan driver to use Raw-IP

```
echo Y > /sys/class/net/wwan0/qmi/raw_ip
```
