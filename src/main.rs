use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::{self, Read, Write};

#[derive(Deserialize)]
struct Input {
    /// List of environment variable names to read
    env_vars: Vec<String>,
}

#[derive(Serialize)]
struct Output {
    /// Map of env var name -> value (or null if not set)
    values: HashMap<String, Option<String>>,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Read input from stdin
    let mut input_string = String::new();
    io::stdin().read_to_string(&mut input_string)?;

    // Parse input JSON
    let input: Input = serde_json::from_str(&input_string)?;

    // Read environment variables
    let mut values = HashMap::new();
    for var_name in input.env_vars {
        let value = std::env::var(&var_name).ok();
        values.insert(var_name, value);
    }

    // Create output
    let output = Output { values };

    // Serialize to JSON and print to stdout
    let json = serde_json::to_string(&output)?;
    print!("{}", json);
    io::stdout().flush()?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_input_parsing() {
        let json = r#"{"env_vars":["PATH","HOME","NONEXISTENT"]}"#;
        let input: Input = serde_json::from_str(json).unwrap();
        assert_eq!(input.env_vars.len(), 3);
        assert_eq!(input.env_vars[0], "PATH");
    }

    #[test]
    fn test_output_serialization() {
        let mut values = HashMap::new();
        values.insert("FOO".to_string(), Some("bar".to_string()));
        values.insert("BAZ".to_string(), None);
        let output = Output { values };
        let json = serde_json::to_string(&output).unwrap();
        assert!(json.contains("FOO"));
        assert!(json.contains("bar"));
    }
}
