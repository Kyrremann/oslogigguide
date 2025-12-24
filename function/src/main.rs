use axum::{Router, routing::post};

use log::info;
use oslogigguide::handler;

#[tokio::main]
async fn main() {
    env_logger::init();

    let app = Router::new().route("/", post(handler));

    let addr = "0.0.0.0:8080";
    info!("Starting server on {}...", addr);
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
