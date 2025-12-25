mod git;

use axum::body::Body;
use axum::http::{self, HeaderValue};
use axum::response::IntoResponse;
use axum::{extract::Json, http::StatusCode};
use log::{error, info};
use serde::Deserialize;
use std::fs;
use std::path::Path;

#[derive(Deserialize)]
pub struct PostRequest {
    user: String,
    token: String,
    id: String,
    #[serde(default)]
    name: String,
}

pub fn with_permissive_cors(origin: String) -> http::HeaderMap {
    let mut headers = http::HeaderMap::new();
    headers.insert(
        "Access-Control-Allow-Headers",
        HeaderValue::from_static("content-type, x-auth-token, authorization, origin, accept"),
    );
    headers.insert(
        "Access-Control-Allow-Methods",
        HeaderValue::from_static("OPTIONS, POST"),
    );

    if origin == "http://localhost:4000" || origin == "https://kyrremann.no" {
        // return response.header("Access-Control-Allow-Origin", origin);
        headers.insert(
            "Access-Control-Allow-Origin",
            HeaderValue::from_str(&origin).unwrap(),
        );
    }

    headers
}

pub async fn handle(
    request: axum::extract::Request<Body>,
) -> Result<impl IntoResponse, (StatusCode, String)> {
    // ) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    // Response<Body> {
    // Json(payload): Json<PostRequest>) -> impl IntoResponse {

    if let Err(e) = env_logger::try_init() {
        error!("Failed to initialize logger: {}", e);
    }

    let origin = match request
        .headers()
        .get("origin")
        .and_then(|v| v.to_str().ok())
    {
        Some(value) => value.to_string(),
        None => {
            error!("Origin header missing or invalid");
            return Err((
                StatusCode::BAD_REQUEST,
                "Origin header missing or invalid".to_string(),
            ));
        }
    };

    info!("Request from origin: {}", origin);
    let headers = with_permissive_cors(origin.clone());

    // Check if this is an OPTIONS request
    if request.method() == http::Method::OPTIONS {
        return Ok((
            StatusCode::OK,
            headers,
            Json(serde_json::json!({
                "message": "CORS preflight successful"
            })),
        ));
    }

    let body_bytes = axum::body::to_bytes(request.into_body(), usize::MAX)
        .await
        .unwrap();

    let payload: PostRequest = serde_json::from_slice(&body_bytes).unwrap();

    // Access the fields
    let user = payload.user;
    let token = payload.token;
    let id = payload.id;
    let name = payload.name;

    // Log the received payload for debugging
    info!(
        "Received subscription request: user={}, id={}, name={}",
        user, id, name
    );

    if token.is_empty() || token != std::env::var("TOKEN").unwrap_or_default() {
        return Err((StatusCode::UNAUTHORIZED, "Unauthorized".to_string()));
    }

    let github_token = std::env::var("GITHUB_TOKEN").map_err(|_| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            "GITHUB_TOKEN not set".to_string(),
        )
    })?;

    let repository = git::clone_repository(&github_token).await.map_err(|err| {
        error!("Failed to clone repository: {err}");
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            "Failed to clone repository".to_string(),
        )
    })?;

    let file_in_git = "_data/calendars.json";
    let message;

    // Subscribe if name is not empty
    if name.is_empty() {
        message = format!("Unsubscribe {} from {}", user, id);
        unsubscribe(&repository, file_in_git, &user, &id).map_err(|err| {
            error!("Failed to remove subscription: {err}");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to remove subscription".to_string(),
            )
        })?;
    } else {
        message = format!("Subscribe {} to {}", user, name);
        subscribe(&repository, file_in_git, &user, &id, &name).map_err(|err| {
            error!("Failed to add subscription: {err}");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to add subscription".to_string(),
            )
        })?;
    }

    git::commit_and_push(repository, &github_token, file_in_git, &message)
        .await
        .map_err(|err| {
            error!("Failed to commit and push: {err}");
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                "Failed to commit and push".to_string(),
            )
        })?;

    Ok((
        StatusCode::OK,
        headers,
        Json(serde_json::json!({
            "status": "success",
            "message": message
        })),
    ))
}

fn unsubscribe(
    _repository: &git2::Repository,
    _file_path: &str,
    _user: &str,
    _id: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let full_path = _repository.path().parent().unwrap().join(_file_path);
    let mut data: serde_json::Value = if Path::new(&full_path).exists() {
        let content = fs::read_to_string(&full_path)?;
        serde_json::from_str(&content)?
    } else {
        serde_json::json!({})
    };

    if let Some(user_entry) = data.as_object_mut().unwrap().get_mut(_user) {
        let subscriptions = user_entry.as_array_mut().unwrap();
        subscriptions.retain(|s| s["id"] != _id);

        // If the user's subscription list is empty, remove the user entry
        if subscriptions.is_empty() {
            data.as_object_mut().unwrap().remove(_user);
        }
    }

    // Write back to the file
    let updated_content = serde_json::to_string_pretty(&data)?;
    fs::write(&full_path, updated_content)?;

    Ok(())
}

fn subscribe(
    repository: &git2::Repository,
    file_path: &str,
    user: &str,
    id: &str,
    name: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    // Read the existing file
    let full_path = repository.path().parent().unwrap().join(file_path);
    info!("Full path to JSON file: {:?}", full_path);
    let mut data: serde_json::Value = if Path::new(&full_path).exists() {
        let content = fs::read_to_string(&full_path)?;
        serde_json::from_str(&content)?
    } else {
        serde_json::json!({})
    };

    // Update the JSON data
    let user_entry = data
        .as_object_mut()
        .unwrap()
        .entry(user.to_string())
        .or_insert_with(|| serde_json::json!([]));

    let subscriptions = user_entry.as_array_mut().unwrap();

    // Check if the subscription already exists
    if !subscriptions.iter().any(|s| s["id"] == id) {
        subscriptions.push(serde_json::json!({
            "id": id,
            "name": name
        }));
    }

    // Write back to the file
    let updated_content = serde_json::to_string_pretty(&data)?;
    fs::write(&full_path, updated_content)?;

    Ok(())
}
