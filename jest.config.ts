export default {
    preset: "ts-jest",
    testEnvironment: "node",
    testPathIgnorePatterns: ["/node_modules/", "/dist/", "proofs.spec.ts", "factory.spec.ts"],
    testTimeout: 30000, // 30 seconds timeout for all tests
}
