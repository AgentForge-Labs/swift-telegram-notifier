Pod::Spec.new do |s|
  s.name         = "AgentForgeTelegramNotifier"
  s.version      = "0.2.0"
  s.summary      = "Native Swift client for AgentForge Telegram Notifier."
  s.description  = "Async/await Swift client for Telegram Notifier inbox, notify, reply and file operations."
  s.homepage     = "https://github.com/AgentForge-Labs/swift-telegram-notifier"
  s.license      = { :type => "AGPL-3.0-only", :file => "LICENSE" }
  s.author       = { "AgentForge Labs" => "opensource@agentforge.dev" }
  s.source       = {
    :git => "https://github.com/AgentForge-Labs/swift-telegram-notifier.git",
    :tag => "v#{s.version}"
  }
  s.source_files = "Sources/AgentForgeTelegramNotifier/**/*.swift"
  s.swift_version = "5.9"
  s.ios.deployment_target = "15.0"
  s.osx.deployment_target = "12.0"
  s.tvos.deployment_target = "15.0"
  s.watchos.deployment_target = "8.0"
end
