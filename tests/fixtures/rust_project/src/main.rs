use std::io;
use std::collections::HashMap;
use tokio::runtime::Runtime;
use serde::{Serialize, Deserialize};
use axum::{Router, routing::get};
use crate::models::User;

mod models;
mod handlers;

pub trait Repository {
    fn find(&self, id: u64) -> Option<User>;
    fn save(&self, user: &User) -> Result<(), String>;
}

pub struct AppState {
    pub db: sqlx::PgPool,
    pub cache: HashMap<String, String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Config {
    pub port: u16,
    pub host: String,
}

impl AppState {
    pub fn new(pool: sqlx::PgPool) -> Self {
        Self {
            db: pool,
            cache: HashMap::new(),
        }
    }
}

impl Config {
    pub fn from_env() -> Self {
        Config {
            port: 8080,
            host: String::from("0.0.0.0"),
        }
    }
}

pub async fn health_check() -> &'static str {
    "OK"
}

fn setup_router() -> Router {
    Router::new().route("/health", get(health_check))
}

unsafe fn raw_pointer_op(ptr: *const u8) -> u8 {
    *ptr
}

unsafe impl Send for AppState {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config() {
        let config = Config::from_env();
        assert_eq!(config.port, 8080);
    }

    #[test]
    fn test_health() {
        assert_eq!(health_check(), "OK");
    }

    #[test]
    fn test_state() {
        // placeholder
    }
}
