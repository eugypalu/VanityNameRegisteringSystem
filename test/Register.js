const { expect } = require("chai");
const { ethers } = require('hardhat');

describe("Register", function () {

    let Register;
    let addr0;
    let addr1;
    let addrs;
    const minCommitmentAge = 1;
    const maxCommitmentAge = 1000;
    const costPerYear = 1;
    const maxYear = 5;
    const url = "url";
    const waitPeriod = 10;
    const oneYear = 365 * 1 * 24 * 60 * 60;
    const provider = waffle.provider;

    function getTransactionGas(receipt) {
        return ethers.utils.parseEther(ethers.utils.formatEther(receipt.gasUsed.mul(receipt.effectiveGasPrice)))
    }

    beforeEach(async function () {
        Register = await ethers.getContractFactory("Register");
        [addr0, addr1, ...addrs] = await ethers.getSigners();
        register = await Register.deploy(minCommitmentAge, maxCommitmentAge, costPerYear, maxYear, url, waitPeriod);
        await register.deployed();
    });

    describe("Register", function () {
        it("Should commit", async function () {

            let secret = ethers.utils.formatBytes32String("secretvalue")
            let commitment = register.makeCommitment("testName", addr0.address, secret);
            await register.commit(commitment);

            expect(register.register("testName", addr1.address, secret, 2)).to.be.revertedWith("too early");
            expect(register.register("testName", addr0.address, secret, maxYear + 1)).to.be.revertedWith("too long");
            expect(register.register("testName", addr0.address, secret, maxYear, {value: 0})).to.be.revertedWith("not enough value");
            
            await register.register("testName", addr0.address, secret, maxYear, {value: costPerYear * maxYear})

            expect(register.register("testName", addr0.address, secret, maxYear, {value: costPerYear * maxYear})).to.be.revertedWith("already registered");

            const commitmentRes = await register.names(commitment);

            expect(commitmentRes.owner).to.equal(addr0.address);
            expect(commitmentRes.amountLocked).to.equal(costPerYear * maxYear);
            expect(commitmentRes.tokenId).to.equal(BigInt(1));
        });

        it("Should transfer 1 token (vanity name)", async function () {

            let secret = ethers.utils.formatBytes32String("secretvalue")
            let commitment = register.makeCommitment("testName", addr0.address, secret);
            await register.commit(commitment);
            
            await register.register("testName", addr0.address, secret, maxYear, {value: costPerYear * maxYear})

            let commitmentRes = await register.names(commitment);

            expect(commitmentRes.owner).to.equal(addr0.address);
            expect(commitmentRes.amountLocked).to.equal(costPerYear * maxYear);
            expect(commitmentRes.tokenId).to.equal(BigInt(1));

            let addr0Balance = await register.balanceOf(addr0.address, 1);
            let addr1Balance = await register.balanceOf(addr1.address, 1);

            let tx = await register.safeTransferFrom(addr0.address, addr1.address, 1, 1, "0x0000000000000000000000000000000000000000000000000000000000000000");

            expect(addr0Balance - 1).to.equal(await register.balanceOf(addr0.address, 1));

            expect(addr1Balance + 1).to.equal(await register.balanceOf(addr1.address, 1));

            commitmentRes = await register.names(await register.namesById(1));

            expect(commitmentRes.owner).to.equal(addr1.address);
        });

        it("Should burn 1 token (vanity name)", async function () {

            let secret = ethers.utils.formatBytes32String("secretvalue")
            let commitment = register.makeCommitment("testName", addr0.address, secret);
            await register.commit(commitment);
            
            await register.register("testName", addr0.address, secret, maxYear, {value: costPerYear * maxYear})

            let commitmentRes = await register.names(commitment);

            expect(commitmentRes.owner).to.equal(addr0.address);
            expect(commitmentRes.amountLocked).to.equal(costPerYear * maxYear);
            expect(commitmentRes.tokenId).to.equal(BigInt(1));

            let addr0Balance = await register.balanceOf(addr0.address, 1);

            await register.burn(addr0.address, 1, 1);

            expect(addr0Balance - 1).to.equal(await register.balanceOf(addr0.address, 1));

            commitmentRes = await register.names(await register.namesById(1));

            expect(commitmentRes.owner).to.equal("0x0000000000000000000000000000000000000000");
            expect(commitmentRes.tokenId).to.equal(0);
        });

        it("Should refund", async function () {

            let secret = ethers.utils.formatBytes32String("secretvalue")
            let commitment = register.makeCommitment("testName", addr0.address, secret);
            await register.commit(commitment);
            
            await register.register("testName", addr0.address, secret, maxYear, {value: costPerYear * maxYear})

            let commitmentRes = await register.names(commitment);

            expect(commitmentRes.owner).to.equal(addr0.address);
            expect(commitmentRes.amountLocked).to.equal(costPerYear * maxYear);
            expect(commitmentRes.tokenId).to.equal(BigInt(1));

            commitmentRes = await register.names(await register.namesById(1));

            expect(register.refundEth(await register.namesById(1))).to.be.revertedWith("not already expired");
            expect(register.refundEth(await register.namesById(1), {from: addr1.address})).to.be.revertedWith("not owner");

            await ethers.provider.send('evm_increaseTime', [maxYear * oneYear * 2]);
            await ethers.provider.send('evm_mine');

            let addr0Balance = await provider.getBalance(addr0.address)

            let tx = await register.refundEth(await register.namesById(1))
            const receipt = await tx.wait()

            expect(addr0Balance.toBigInt() - getTransactionGas(receipt).toBigInt() + commitmentRes.amountLocked.toBigInt()).to.equal(await provider.getBalance(addr0.address));
        });

        it("Should renew the vanity name", async function () {

            let secret = ethers.utils.formatBytes32String("secretvalue")
            let commitment = register.makeCommitment("testName", addr0.address, secret);
            await register.commit(commitment);
            
            await register.register("testName", addr0.address, secret, maxYear, {value: costPerYear * maxYear})

            let commitmentRes = await register.names(commitment);

            expect(commitmentRes.owner).to.equal(addr0.address);
            expect(commitmentRes.amountLocked).to.equal(costPerYear * maxYear);
            expect(commitmentRes.tokenId).to.equal(BigInt(1));

            commitmentRes = await register.names(await register.namesById(1));

            await ethers.provider.send('evm_increaseTime', [maxYear]);
            await ethers.provider.send('evm_mine');

            await register.renew(await register.namesById(1), maxYear, {value: costPerYear * maxYear});

            await ethers.provider.send('evm_increaseTime', [waitPeriod + 10]);
            await ethers.provider.send('evm_mine');

            expect(register.renew(await register.namesById(1), maxYear, {value: costPerYear * maxYear})).to.be.revertedWith("is expired");
        });
    });
});