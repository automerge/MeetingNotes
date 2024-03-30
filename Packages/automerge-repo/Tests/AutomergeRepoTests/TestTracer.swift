import Foundation
import Logging
import OTel
import OTLPGRPC
import ServiceLifecycle
import Tracing

@globalActor
public actor TestTracer {
    private var bootstrapped = false
    public static let shared = TestTracer()

    var tracer: OTelTracer<
        OTelRandomIDGenerator<SystemRandomNumberGenerator>,
        OTelConstantSampler,
        OTelW3CPropagator,
        OTelBatchSpanProcessor<OTLPGRPCSpanExporter, ContinuousClock>,
        ContinuousClock
    >?

    func bootstrap() async {
        if !bootstrapped {
            let environment = OTelEnvironment.detected()
            let resourceDetection = OTelResourceDetection(detectors: [
                OTelProcessResourceDetector(),
                OTelEnvironmentResourceDetector(environment: environment),
                .manual(OTelResource(attributes: ["service.name": "TwoRepoTest"])),
            ])

            let resource: OTelResource = await resourceDetection.resource(environment: environment, logLevel: .trace)

            /*
             Bootstrap the logging system to use the OTel metadata provider.
             This will automatically include trace and span IDs in log statements
             from your app and its dependencies.
             */
            LoggingSystem.bootstrap({ label, _ in
                var handler = StreamLogHandler.standardOutput(label: label)
                // We set the lowest possible minimum log level to see all log statements.
                handler.logLevel = .trace
                return handler
            }, metadataProvider: .otel)

            let logger = Logger(label: "example")
            logger.debug("TEST MARKER")

            // Here we create an OTel span exporter that sends spans via gRPC to an OTel collector.
            let exporter = try! OTLPGRPCSpanExporter(configuration: .init(environment: environment))
            /*
             This exporter is passed to a batch span processor.
             The processor receives ended spans from the tracer, batches them up, and finally forwards them to the exporter.
             */
            let processor = OTelBatchSpanProcessor(exporter: exporter, configuration: .init(environment: environment))
            /*
             We need to await tracer initialization since the tracer needs
             some time to detect attributes about the resource being traced.
             */
            let myTracer = OTelTracer(
                idGenerator: OTelRandomIDGenerator(),
                sampler: OTelConstantSampler(isOn: true),
                propagator: OTelW3CPropagator(),
                processor: processor,
                environment: environment,
                resource: resource
            )
            /*
             Once we have a tracer, we bootstrap the instrumentation system to use it.
             This configures your application code and any of your dependencies to use the OTel tracer.
             */
            InstrumentationSystem.bootstrap(myTracer)

            let serviceGroup = ServiceGroup(
                services: [myTracer],
                gracefulShutdownSignals: [.sigint],
                logger: logger
            )

            // Set up a detached task to run this in the background indefinitely.
            // - no cancellation, just GO
            Task {
                try await serviceGroup.run()
            }

            bootstrapped = true
            tracer = myTracer
        }
    }

    init() {}
}
