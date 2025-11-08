fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::compile_protos("./proto/user_service.proto")?;
    tonic_build::compile_protos("./proto/report_service.proto")?;
    Ok(())
}
