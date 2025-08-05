import {Cell} from "@ton/core"
import {runTolkCompiler, TolkCompilerConfig} from "@ton/tolk-js"
import {ContractName, DEX_SOURCES} from "./sources"
import {readFileSync, writeFileSync, mkdirSync} from "fs"
import {join} from "path"

async function doCompileTolk(config: TolkCompilerConfig) {
    const res = await runTolkCompiler(config)

    if (res.status === "error") {
        // if we throw error here, it will
        // unroll stack trace with wasm errors,
        // so better we handle it ourselves
        console.error(res.message)
        process.exit(-1)
    }

    return {
        stderr: res.stderr,
        fiftCode: res.fiftCode,
        code: Cell.fromBase64(res.codeBoc64),
    }
}

export const compileContract = async (name: ContractName) => {
    const path = DEX_SOURCES[name]

    const result = await doCompileTolk({
        entrypointFileName: path,
        fsReadCallback: data => readFileSync(data).toString(),
        withStackComments: true,
        withSrcLineComments: true,
        experimentalOptions: "",
    })

    if (result.stderr !== "") {
        console.error(result.stderr)
    }

    return {
        code: result.code,
        fift: result.fiftCode,
    }
}

const contractNames = () => Object.keys(DEX_SOURCES) as ContractName[]

export const compileAll = async () => {
    const sources: Record<ContractName, Cell> = {} as any
    const names = contractNames()

    // Ensure output directory exists
    const outputDir = join(__dirname, "../../sources/fift-output")
    mkdirSync(outputDir, {recursive: true})

    for (const name of names) {
        const codeCell = await compileContract(name as ContractName)
        sources[name] = codeCell.code

        // Write Fift code to output file
        const fiftFileName = `${name}.fif`
        const fiftFilePath = join(outputDir, fiftFileName)
        writeFileSync(fiftFilePath, codeCell.fift)
    }

    return sources
}
