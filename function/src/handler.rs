mod git;

use axum::{extract::Json, http::StatusCode, response::IntoResponse};
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

pub async fn handle(Json(payload): Json<PostRequest>) -> impl IntoResponse {
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

    let response = serde_json::json!({
        message: "Subscription added successfully".to_string(),
    });
    Ok((StatusCode::OK, Json(response)))
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
