import { ethers } from "hardhat"

async function main() {
    const DividendSplitterFactory = await ethers.getContractFactory("DividendSplitter")
    const dividendSplitter = await DividendSplitterFactory.deploy()

    console.log("DividendSplitter deployed to:", await dividendSplitter.getAddress())
}

main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
