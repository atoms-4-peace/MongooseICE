defmodule Helper.UDP do
  use ExUnit.Case

  alias Jerboa.Params
  alias Jerboa.Format
  alias Jerboa.Format.Body.Attribute.{Username, RequestedTransport,
                                      XORPeerAddress}

  import Mock

  @recv_timeout 5_000
  @default_user "user"

  ## Requests definitions

  def binding_request(id) do
    %Params{class: :request, method: :binding, identifier: id} |> Format.encode()
  end

  def binding_indication(id) do
    %Params{class: :indication, method: :binding, identifier: id} |> Format.encode()
  end

  def allocate_request(id) do
    allocate_request(id, [%RequestedTransport{protocol: :udp}])
  end

  def create_permission_params(id, attrs) do
    %Params{class: :request, method: :create_permission, identifier: id,
            attributes: attrs}
  end

  def create_permission_request(id, attrs) do
    create_permission_params(id, attrs)
    |> Format.encode()
  end

  def allocate_params(id, attrs) do
    %Params{class: :request, method: :allocate, identifier: id,
            attributes: attrs}
  end

  def allocate_request(id, attrs) do
    allocate_params(id, attrs)
    |> Format.encode()
  end

  def peers(peers) do
    for ip <- peers do
      %XORPeerAddress{
        address: ip,
        port: 0,
        family: Fennec.Evaluator.Helper.family(ip)
      }
    end
  end

  ## UDP Client

  def allocate(udp, username \\ @default_user, client_id \\ 0) do
    id = Params.generate_id()
    req = allocate_request(id, [
      %RequestedTransport{protocol: :udp},
      %Username{value: username}
    ])
    resp = communicate(udp, client_id, req)
    params = Format.decode!(resp)
    %Params{class: :success,
            method: :allocate,
            identifier: ^id} = params
  end

  def create_permissions(udp, ips, username \\ @default_user, client_id \\ 0) do
    id = Params.generate_id()
    req = create_permission_request(id, peers(ips) ++ [
      %Username{value: username}
    ])
    resp = communicate(udp, client_id, req)
    params = Format.decode!(resp)
    %Params{class: :success,
            method: :create_permission,
            identifier: ^id} = params
  end

  ## Communication

  def connect(server_address, server_port, client_address, client_port,
                   client_count) do
    Application.put_env(:fennec, :relay_addr, server_address)
    Fennec.UDP.start_link(ip: server_address, port: server_port,
                          relay_ip: server_address)

    sockets =
      for i <- 1..client_count do
        {:ok, sock} =
          :gen_udp.open(client_port + i,
                        [:binary, active: false, ip: client_address])
          sock
      end

    %{
      server_address: server_address,
      server_port: server_port,
      client_address: client_address,
      client_port_base: client_port,
      sockets: sockets
    }
  end

  def close(%{sockets: sockets}) do
    for sock <- sockets do
      :gen_udp.close(sock)
    end
  end

  def send(udp, client_id, req) do
    sock = Enum.at(udp.sockets, client_id)
    :ok = :gen_udp.send(sock, udp.server_address, udp.server_port, req)
  end

  def recv(udp, client_id) do
    %{server_address: server_address, server_port: server_port} = udp
    {sock, _} = List.pop_at(udp.sockets, client_id)
    {:ok, {^server_address,
           ^server_port,
           resp}} = :gen_udp.recv(sock, 0, @recv_timeout)
    resp
  end

  def communicate(udp, client_id, req) do
    with_mock Fennec.Auth, [:passthrough], [
      maybe: fn(_, p, _, _) -> {:ok, p} end
    ] do
     :ok = send(udp, client_id, req)
     recv(udp, client_id)
   end
  end

  def client_port(udp, client_id) do
     udp.client_port_base + client_id + 1
  end
end