import CoreFoundation
import Darwin
import Foundation

/// 温度采集：Apple Silicon 上走 IOHIDEventSystemClient 读取片上温度传感器。
///
/// 这套接口是 IOKit 的**未公开 API**（Stats 等开源监控工具同样使用它），
/// 因此在链接期不能声明符号，全部通过 `dlopen` + `dlsym` 在运行时解析。
/// 好处是符号不存在时只会降级，不会让整个 App 起不来。
final class TemperatureCollector {

    private typealias HIDClient = OpaquePointer
    private typealias HIDService = OpaquePointer
    private typealias HIDEvent = OpaquePointer

    private typealias CreateFn      = @convention(c) (UnsafeRawPointer?) -> HIDClient?
    private typealias CopyServicesFn = @convention(c) (HIDClient) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (HIDService, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn    = @convention(c) (HIDService, Int32, Int32, Int64) -> HIDEvent?
    private typealias GetFloatFn     = @convention(c) (HIDEvent, Int32) -> Double

    private struct Symbols {
        let copyServices: CopyServicesFn
        let copyProperty: CopyPropertyFn
        let copyEvent: CopyEventFn
        let getFloat: GetFloatFn
    }

    private var handle: UnsafeMutableRawPointer?
    private var symbols: Symbols?
    private var client: HIDClient?
    private var didLoad = false

    /// kIOHIDEventTypeTemperature = 15；IOHIDEventFieldBase(type) = type << 16
    private static let temperatureEventType: Int32 = 15
    private static let temperatureField: Int32 = 15 << 16

    deinit {
        if let client {
            // IOHIDEventSystemClient 是 CFType，用 CFRelease 释放
            Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(client)).release()
        }
        if let handle { dlclose(handle) }
    }

    // MARK: - 对外采样

    func sample(batteryFallback: Double?) -> TempStatus {
        var status = TempStatus()

        if !didLoad { load() }

        if let readings = readAllSensors(), !readings.isEmpty {
            var cpuCores: [Double] = []
            var socCores: [Double] = []
            var gpuCores: [Double] = []
            var batteryCores: [Double] = []

            for reading in readings {
                let name = reading.name.lowercased()
                if name.contains("battery") || name.contains("gas gauge") {
                    batteryCores.append(reading.celsius)
                } else if name.contains("gpu") {
                    gpuCores.append(reading.celsius)
                } else if name.contains("tdie") || name.contains("cpu") || name.contains("soc") || name.contains("pmu") {
                    cpuCores.append(reading.celsius)
                    socCores.append(reading.celsius)
                }
            }

            status.cpuC = Self.average(cpuCores)
            status.socC = Self.average(socCores)
            status.gpuC = Self.average(gpuCores)
            status.batteryC = Self.average(batteryCores) ?? batteryFallback
            status.sensorCount = readings.count

            if status.cpuC != nil {
                status.source = L.f("HID 传感器 · %@ 路", readings.count)
            } else if status.batteryC != nil {
                status.source = L.t("电池温度回退")
            }
        }

        // 完全没有片上传感器时，退回 IORegistry 的电池温度
        if status.cpuC == nil, let batteryFallback, batteryFallback > 0 {
            status.batteryC = batteryFallback
            status.source = L.t("电池温度回退")
        }

        if status.source == "—" {
            status.source = L.t("不可用")
        }
        return status
    }

    // MARK: - 符号加载

    private func load() {
        didLoad = true
        let path = "/System/Library/Frameworks/IOKit.framework/IOKit"
        guard let handle = dlopen(path, RTLD_LAZY) else { return }
        self.handle = handle

        guard
            let createPtr = dlsym(handle, "IOHIDEventSystemClientCreate"),
            let servicesPtr = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
            let propertyPtr = dlsym(handle, "IOHIDServiceClientCopyProperty"),
            let eventPtr = dlsym(handle, "IOHIDServiceClientCopyEvent"),
            let floatPtr = dlsym(handle, "IOHIDEventGetFloatValue")
        else { return }

        let create = unsafeBitCast(createPtr, to: CreateFn.self)
        symbols = Symbols(
            copyServices: unsafeBitCast(servicesPtr, to: CopyServicesFn.self),
            copyProperty: unsafeBitCast(propertyPtr, to: CopyPropertyFn.self),
            copyEvent: unsafeBitCast(eventPtr, to: CopyEventFn.self),
            getFloat: unsafeBitCast(floatPtr, to: GetFloatFn.self)
        )

        client = create(nil)
    }

    // MARK: - 读取

    private struct Reading {
        let name: String
        let celsius: Double
    }

    private func readAllSensors() -> [Reading]? {
        guard let symbols, let client else { return nil }
        guard let servicesRef = symbols.copyServices(client) else { return nil }
        let services = servicesRef.takeRetainedValue() as [AnyObject]

        var readings: [Reading] = []
        readings.reserveCapacity(services.count)

        for element in services {
            let service = HIDService(UnsafeRawPointer(Unmanaged.passUnretained(element).toOpaque()))
            guard let nameRef = symbols.copyProperty(service, "Product" as CFString) else { continue }
            let nameValue = nameRef.takeRetainedValue()
            guard let name = nameValue as? String, !name.isEmpty else { continue }

            guard let event = symbols.copyEvent(service, Self.temperatureEventType, 0, 0) else { continue }
            let celsius = symbols.getFloat(event, Self.temperatureField)
            Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(event)).release()

            guard celsius > 0, celsius < 150 else { continue }
            readings.append(Reading(name: name, celsius: celsius))
        }
        return readings
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// 诊断用：列出所有传感器名字与温度，便于确认不同机型上的命名
    func dumpSensors() -> [String] {
        if !didLoad { load() }
        guard let readings = readAllSensors() else { return [] }
        return readings.map { "\($0.name) = \(String(format: "%.2f", $0.celsius))°C" }
    }
}
