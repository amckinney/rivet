use chirp_worker::prelude::*;

use ::mm_gc_full::run_from_env;

#[tokio::test(flavor = "multi_thread")]
async fn all() {
	// Run tests sequentially so the gc's don't interfere with each other

	tracing_subscriber::fmt()
		.json()
		.with_max_level(tracing::Level::INFO)
		.with_span_events(tracing_subscriber::fmt::format::FmtSpan::NONE)
		.init();

	run_from_env(util::timestamp::now()).await.unwrap();
}
