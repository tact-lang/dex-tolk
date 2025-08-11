import {compileAll} from "./compile"

const main = async () => {
    const res = await compileAll()

    // maybe write fift to output
    // or save boc to filesystem later
    console.log(`Successfully compiled ${Object.keys(res).length} tolk contracts`)
}

main()
