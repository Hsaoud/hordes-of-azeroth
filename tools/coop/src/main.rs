mod ticket;

use anyhow::{Context, Result, bail};
use iroh::{Endpoint, EndpointId, SecretKey, endpoint::presets};
use rand::RngCore;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{net::Ipv4Addr, sync::Arc, time::Duration};
use subtle::ConstantTimeEq;
use tokio::{io::{AsyncBufReadExt, AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, BufReader}, net::{TcpListener, TcpStream}, sync::{Semaphore, mpsc}, time::timeout};
use tokio_util::sync::CancellationToken;

const ALPN: &[u8] = b"hordes-of-azeroth/coop/1";
const MAX_CONTROL: usize = 8192;
const DEADLINE: Duration = Duration::from_secs(45);

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Config {
    mode: String,
    version: String,
    #[serde(default)]
    code: String,
    identity: String,
    #[serde(default = "login_port")]
    login_port: u16,
    #[serde(default = "world_port")]
    world_port: u16,
    #[serde(default)]
    direct_only: bool,
    #[serde(default)]
    relay_only: bool,
}

fn login_port() -> u16 { 3724 }
fn world_port() -> u16 { 8085 }

#[derive(Serialize, Deserialize)]
struct Hello {
    version: String,
    secret: String,
    password: String,
}

fn event(value: Value) {
    println!("{value}");
}

async fn write_json<W: AsyncWrite + Unpin, T: Serialize>(writer: &mut W, value: &T) -> Result<()> {
    let bytes = serde_json::to_vec(value)?;
    if bytes.len() > MAX_CONTROL { bail!("control-too-large") }
    writer.write_u32(bytes.len() as u32).await?;
    writer.write_all(&bytes).await?;
    writer.flush().await?;
    Ok(())
}

async fn read_json<R: AsyncRead + Unpin, T: for<'de> Deserialize<'de>>(reader: &mut R) -> Result<T> {
    let length = reader.read_u32().await? as usize;
    if length == 0 || length > MAX_CONTROL { bail!("invalid-control") }
    let mut bytes = vec![0; length];
    reader.read_exact(&mut bytes).await?;
    Ok(serde_json::from_slice(&bytes)?)
}

async fn forward(tcp: TcpStream, mut send: iroh::endpoint::SendStream, mut recv: iroh::endpoint::RecvStream) -> Result<()> {
    tcp.set_nodelay(true)?;
    let (mut reader, mut writer) = tcp.into_split();
    let up = async {
        tokio::io::copy(&mut reader, &mut send).await?;
        send.shutdown().await?;
        Ok::<_, anyhow::Error>(())
    };
    let down = async {
        tokio::io::copy(&mut recv, &mut writer).await?;
        writer.shutdown().await?;
        Ok::<_, anyhow::Error>(())
    };
    tokio::try_join!(up, down)?;
    Ok(())
}

fn account_for(id: EndpointId) -> String {
    let digest = Sha256::digest(id.as_bytes());
    let text = data_encoding::HEXUPPER.encode(&digest);
    format!("COOP{}", &text[..12])
}

async fn serve_guest(conn: iroh::endpoint::Connection, cfg: &Config, secret: &[u8; 16], commands: &mut mpsc::Receiver<Value>) -> Result<()> {
    let (mut send, mut recv) = timeout(DEADLINE, conn.accept_bi()).await??;
    let hello: Hello = timeout(DEADLINE, read_json(&mut recv)).await??;
    let supplied = data_encoding::HEXUPPER.decode(hello.secret.as_bytes()).unwrap_or_default();
    if !bool::from(supplied.as_slice().ct_eq(secret)) {
        write_json(&mut send, &json!({"error":"invalid-code"})).await?;
        bail!("invalid-code")
    }
    if hello.version != cfg.version {
        write_json(&mut send, &json!({"error":"version-mismatch"})).await?;
        bail!("version-mismatch")
    }
    if hello.password.len() != 16 || !hello.password.bytes().all(|c| c.is_ascii_hexdigit()) { bail!("invalid-profile") }
    let account = account_for(conn.remote_id());
    let password = hello.password;
    event(json!({"event":"guest", "account":account, "password":password}));
    let admitted = timeout(DEADLINE, commands.recv()).await?.context("launcher-closed")?;
    if admitted["command"] != "admit" {
        write_json(&mut send, &json!({"error":"host-not-ready"})).await?;
        bail!("host-not-ready")
    }
    write_json(&mut send, &json!({"ready":true, "account":account, "password":password, "profile":admitted.get("profile")})).await?;
    event(json!({"event":"connected"}));
    let limit = Arc::new(Semaphore::new(8));
    let mut streams = tokio::task::JoinSet::new();
    loop {
        tokio::select! {
            incoming = conn.accept_bi() => {
                let (send, mut recv) = incoming?;
                let Ok(permit) = limit.clone().try_acquire_owned() else { continue };
                let login = cfg.login_port;
                let world = cfg.world_port;
                streams.spawn(async move {
                    let _permit = permit;
                    let channel = timeout(Duration::from_secs(10), recv.read_u8()).await??;
                    let port = match channel { 1 => login, 2 => world, _ => bail!("invalid-channel") };
                    let tcp = timeout(Duration::from_secs(10), TcpStream::connect((Ipv4Addr::LOCALHOST, port))).await??;
                    forward(tcp, send, recv).await
                });
            }
            closed = conn.closed() => { bail!("{closed}") }
            _ = streams.join_next(), if !streams.is_empty() => {}
        }
    }
}

async fn host(endpoint: &Endpoint, cfg: &Config, commands: &mut mpsc::Receiver<Value>) -> Result<()> {
    let mut secret = [0; 16];
    rand::rng().fill_bytes(&mut secret);
    timeout(DEADLINE, endpoint.online()).await?;
    event(json!({"event":"hosting", "code":ticket::encode(endpoint.id().as_bytes(), &secret)}));
    while let Some(incoming) = endpoint.accept().await {
        let conn = match timeout(Duration::from_secs(15), incoming).await {
            Ok(Ok(conn)) => conn,
            _ => continue,
        };
        let active = serve_guest(conn.clone(), cfg, &secret, commands);
        tokio::pin!(active);
        loop {
            tokio::select! {
                result = &mut active => {
                    conn.close(0u32.into(), b"guest-left");
                    if result.is_err() { event(json!({"event":"left"})); }
                    break;
                }
                incoming = endpoint.accept() => {
                    if let Some(incoming) = incoming {
                        tokio::spawn(async move {
                            let _ = timeout(Duration::from_secs(5), async move {
                                let conn = incoming.await?;
                                let (mut send, mut recv) = conn.accept_bi().await?;
                                let _: Hello = read_json(&mut recv).await?;
                                write_json(&mut send, &json!({"error":"room-full"})).await?;
                                send.shutdown().await?;
                                let _ = conn.closed().await;
                                Ok::<_, anyhow::Error>(())
                            }).await;
                        });
                    }
                }
            }
        }
    }
    Ok(())
}

async fn join(endpoint: &Endpoint, cfg: &Config) -> Result<()> {
    let (id, secret) = ticket::decode(&cfg.code)?;
    let id = EndpointId::from_bytes(&id)?;
    let conn = timeout(DEADLINE, endpoint.connect(id, ALPN)).await??;
    let (mut send, mut recv) = conn.open_bi().await?;
    let password = data_encoding::HEXUPPER.encode(&Sha256::digest(endpoint.secret_key().to_bytes()));
    write_json(&mut send, &Hello { version: cfg.version.clone(), secret: data_encoding::HEXUPPER.encode(&secret), password: password[..16].to_owned() }).await?;
    let reply: Value = timeout(DEADLINE, read_json(&mut recv)).await??;
    if let Some(error) = reply["error"].as_str() { bail!("{error}") }
    if reply["ready"] != true { bail!("host-not-ready") }
    let login = TcpListener::bind((Ipv4Addr::LOCALHOST, cfg.login_port)).await.context("local-port-in-use")?;
    let world = TcpListener::bind((Ipv4Addr::LOCALHOST, cfg.world_port)).await.context("local-port-in-use")?;
    event(json!({"event":"ready", "account":reply["account"], "password":reply["password"], "profile":reply["profile"]}));
    let limit = Arc::new(Semaphore::new(8));
    let mut streams = tokio::task::JoinSet::new();
    loop {
        let (tcp, channel) = tokio::select! {
            socket = login.accept() => (socket?.0, 1u8),
            socket = world.accept() => (socket?.0, 2u8),
            closed = conn.closed() => { bail!("{closed}") }
            _ = streams.join_next(), if !streams.is_empty() => { continue; }
        };
        let Ok(permit) = limit.clone().try_acquire_owned() else { continue };
        let conn = conn.clone();
        streams.spawn(async move {
            let _permit = permit;
            let (mut send, recv) = conn.open_bi().await?;
            send.write_u8(channel).await?;
            forward(tcp, send, recv).await
        });
    }
}

async fn run() -> Result<()> {
    let mut lines = BufReader::new(tokio::io::stdin()).lines();
    let line = lines.next_line().await?.context("missing-config")?;
    if line.len() > MAX_CONTROL { bail!("invalid-config") }
    let cfg: Config = serde_json::from_str(&line)?;
    if cfg.version.is_empty() || cfg.version.len() > 64 { bail!("invalid-version") }
    let key: [u8; 32] = data_encoding::HEXUPPER.decode(cfg.identity.as_bytes())?.try_into().map_err(|_| anyhow::anyhow!("invalid-identity"))?;
    if cfg.mode == "join" { ticket::decode(&cfg.code)?; }
    let mut builder = Endpoint::builder(presets::N0).secret_key(SecretKey::from_bytes(&key)).alpns(vec![ALPN.to_vec()]);
    if cfg.direct_only { builder = builder.relay_mode(iroh::RelayMode::Disabled); }
    if cfg.relay_only { builder = builder.clear_ip_transports(); }
    let endpoint = builder.bind().await?;
    let cancel = CancellationToken::new();
    let stop = cancel.clone();
    let (tx, mut rx) = mpsc::channel(8);
    tokio::spawn(async move {
        while let Ok(Some(line)) = lines.next_line().await {
            if line.len() > MAX_CONTROL { break; }
            let Ok(command) = serde_json::from_str::<Value>(&line) else { break; };
            if command["command"] == "stop" { break; }
            if tx.send(command).await.is_err() { break; }
        }
        stop.cancel();
    });
    let result = tokio::select! {
        result = async {
            match cfg.mode.as_str() {
                "host" => host(&endpoint, &cfg, &mut rx).await,
                "join" => join(&endpoint, &cfg).await,
                _ => bail!("invalid-mode"),
            }
        } => result,
        _ = cancel.cancelled() => Ok(()),
    };
    endpoint.close().await;
    result
}

#[tokio::main]
async fn main() {
    if let Err(error) = run().await {
        eprintln!("{error:#}");
        let detail = error.to_string();
        let code = ["invalid-code", "version-mismatch", "host-not-ready", "local-port-in-use", "room-full"]
            .into_iter().find(|known| detail.contains(known)).unwrap_or("connection-lost");
        event(json!({"event":"error", "code":code}));
        std::process::exit(1);
    }
}
