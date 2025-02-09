// RUN: %empty-directory(%t)
// RUN: %target-swift-frontend-emit-module -emit-module-path %t/FakeDistributedActorSystems.swiftmodule -module-name FakeDistributedActorSystems -disable-availability-checking %S/../Inputs/FakeDistributedActorSystems.swift -plugin-path %swift-plugin-dir
// RUN: %target-build-swift -module-name main  -Xfrontend -disable-availability-checking -j2 -parse-as-library -I %t %s %S/../Inputs/FakeDistributedActorSystems.swift -plugin-path %swift-plugin-dir -o %t/a.out
// RUN: %target-codesign %t/a.out
// RUN: %target-run %t/a.out | %FileCheck %s --color

// REQUIRES: executable_test
// REQUIRES: concurrency
// REQUIRES: distributed

// rdar://76038845
// UNSUPPORTED: use_os_stdlib
// UNSUPPORTED: back_deployment_runtime

// FIXME(distributed): Distributed actors currently have some issues on windows, isRemote always returns false. rdar://82593574
// UNSUPPORTED: OS=windows-msvc

// FIXME(distributed): pending adjustments in protocol macro to handle == in protocol
// XFAIL: *

import Distributed
import FakeDistributedActorSystems

// ==== Known actor system -----------------------------------------------------

@_DistributedProtocol
protocol GreeterDefinedSystemProtocol: DistributedActor where ActorSystem == FakeRoundtripActorSystem {
  distributed func greet() -> String
}

/// A concrete implementation done on the "server" side of a non-symmetric application
distributed actor GreeterImpl: GreeterDefinedSystemProtocol {
  typealias ActorSystem = FakeRoundtripActorSystem

  distributed func greet() -> String {
    "[IMPL]:Hello from \(Self.self)"
  }
}

// ==== ------------------------------------------------------------------------

@main struct Main {
  static func main() async throws {
    let roundtripSystem = FakeRoundtripActorSystem()

    let real: any GreeterDefinedSystemProtocol = GreeterImpl(actorSystem: roundtripSystem)
    let realGreeting = try await real.greet()
    print("local call greeting: \(realGreeting)")
    // CHECK: local call greeting: [IMPL]:Hello from GreeterImpl

    let proxy: any GreeterDefinedSystemProtocol =
      try $GreeterDefinedSystemProtocol.resolve(id: real.id, using: roundtripSystem)
    let greeting = try await proxy.greet()
    // CHECK: >> remoteCall: on:main.GreeterDefinedSystemProtocol_Stub, target:greet(), invocation:FakeInvocationEncoder(genericSubs: [], arguments: [], returnType: Optional(Swift.String), errorType: nil), throwing:Swift.Never, returning:Swift.String
    // CHECK: > execute distributed target: greet(), identifier: $s4main28GreeterDefinedSystemProtocolP5greetSSyFTE

    // CHECK: << remoteCall return: [IMPL]:Hello from GreeterImpl

    print("protocol call greeting: \(greeting)")
    // CHECK: protocol call greeting: [IMPL]:Hello from GreeterImpl
  }
}


