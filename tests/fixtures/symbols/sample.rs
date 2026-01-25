use std::io::Result;
use std::collections::HashMap;

pub const MAX_SIZE: usize = 1024;

static COUNTER: AtomicUsize = AtomicUsize::new(0);

pub mod utils {
    pub fn helper() -> bool { true }
}

pub struct Config {
    pub host: String,
    pub port: u16,
}

pub enum AppError {
    NotFound,
    Internal(String),
}

pub trait Service {
    fn start(&self) -> Result<()>;
    fn stop(&self) -> Result<()>;
}

impl Config {
    pub fn new(host: &str, port: u16) -> Self {
        Config { host: host.to_string(), port }
    }
}

impl Service for Config {
    fn start(&self) -> Result<()> { Ok(()) }
    fn stop(&self) -> Result<()> { Ok(()) }
}

pub async fn run_server(config: Config) -> Result<()> {
    Ok(())
}

fn internal_helper(x: i32) -> i32 {
    x * 2
}
