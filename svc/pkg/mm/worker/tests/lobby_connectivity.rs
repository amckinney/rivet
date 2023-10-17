mod common;

use chirp_worker::prelude::*;
use common::*;
use proto::backend::pkg::*;
use std::{
	io::{Read, Write},
	net::{TcpStream, UdpSocket},
};

#[worker_test]
async fn lobby_connectivity_http(ctx: TestCtx) {
	if !util::feature::job_run() {
		return;
	}

	let setup = Setup::init(&ctx).await;

	let lobby_id = setup.create_lobby(&ctx).await;

	let (hostname, _) = get_lobby_addr(&ctx, lobby_id, "test-http").await;

	// Echo body
	let random_body = Uuid::new_v4().to_string();
	let client = reqwest::Client::new();
	let res = client
		.post(format!("http://{hostname}"))
		.body(random_body.clone())
		.send()
		.await
		.unwrap()
		.error_for_status()
		.unwrap();
	let res_text = res.text().await.unwrap();
	assert_eq!(random_body, res_text, "echoed wrong response");
}

#[worker_test]
async fn lobby_connectivity_tcp(ctx: TestCtx) {
	if !util::feature::job_run() {
		return;
	}

	let setup = Setup::init(&ctx).await;

	let lobby_id = setup.create_lobby(&ctx).await;

	let (hostname, port) = get_lobby_addr(&ctx, lobby_id, "test-tcp").await;

	// Echo body
	let random_body = Uuid::new_v4();
	let mut stream = TcpStream::connect((hostname, port)).unwrap();

	stream.write_all(random_body.as_ref()).unwrap();
	stream.flush().unwrap();

	let mut response = Vec::new();
	stream.read_to_end(&mut response).unwrap();

	assert_eq!(
		random_body.as_ref(),
		response.as_slice(),
		"echoed wrong response"
	);
}

#[worker_test]
async fn lobby_connectivity_udp(ctx: TestCtx) {
	if !util::feature::job_run() {
		return;
	}

	let setup = Setup::init(&ctx).await;

	let lobby_id = setup.create_lobby(&ctx).await;

	let (hostname, port) = get_lobby_addr(&ctx, lobby_id, "test-udp").await;

	// Echo body
	let random_body = Uuid::new_v4();
	let socket = UdpSocket::bind(("0.0.0.0", 0)).unwrap();
	socket.connect((hostname, port)).unwrap();
	socket.send(random_body.as_ref()).unwrap();

	let mut response = [0; 2048];
	let recv_len = socket.recv(&mut response).unwrap();

	assert_eq!(
		random_body.as_ref(),
		&response[..recv_len],
		"echoed wrong response"
	);
}

/// Fetches the address to get the lobby from.
async fn get_lobby_addr(ctx: &TestCtx, lobby_id: Uuid, port: &str) -> (String, u16) {
	let lobby_res = op!([ctx] mm_lobby_get { lobby_ids: vec![lobby_id.into()] })
		.await
		.unwrap();
	let lobby = lobby_res.lobbies.first().unwrap();
	let run_id = lobby.run_id.unwrap();

	let run_res = op!([ctx] job_run_get { run_ids: vec![run_id] })
		.await
		.unwrap();
	let run = run_res.runs.first().unwrap();

	let port = run
		.proxied_ports
		.iter()
		.find(|x| x.target_nomad_port_label == Some(util_mm::format_nomad_port_label(port)))
		.unwrap();

	(
		port.ingress_hostnames.first().unwrap().clone(),
		port.ingress_port as u16,
	)
}
