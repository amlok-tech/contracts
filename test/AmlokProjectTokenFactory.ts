// @ts-ignore
import {ethers} from "hardhat";
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {expect} from 'chai';
import '@nomicfoundation/hardhat-chai-matchers'
import {time} from "@nomicfoundation/hardhat-network-helpers";
import {Contract} from "ethers";

describe("AmlokProjectTokenFactory", function () {

    let qty = [
        1, 2, 3, 50
    ];

    let master: SignerWithAddress;
    let user: SignerWithAddress;
    let maximumQty = 100;
    let cancelTimeDelaySecond = 365;

    let token: Contract;

    async function CreateFactory() {
        [master, user] = await ethers.getSigners();
        const amlokProjectFactoryFactory = await ethers.getContractFactory("AmlokProjectTokenFactory");
        return await amlokProjectFactoryFactory.deploy(master.address);//royaltyReceiver
    }

    async function deploy() {
        [master, user] = await ethers.getSigners();
        const tokenFactory = await ethers.getContractFactory("SimpleToken")
        token = await tokenFactory.deploy();
        await token.connect(user).mint(1e8);

        let amlokProjectFactory = await CreateFactory();

        const cancelTime = (await time.latest()) + cancelTimeDelaySecond;
        let projectCreateTx = await amlokProjectFactory.createProject(1, "ipfs://contractUri",
            "name",
            "symbol",
            "ipfs://",
            qty,
            token.address,
            maximumQty,
            cancelTime);
        let tx = await projectCreateTx.wait();

        let find = tx.events?.find((n: any) => n.event == 'CreateAmlokProject');
        let args = find?.args;

        if (args != null) {
            let address = args['projectAddress'];
            const amlokProjectFactory = await ethers.getContractFactory("AmlokProjectTokenUpgradable");

            await token.connect(user).approve(address, "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
            await token.connect(master).approve(address, "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

            return amlokProjectFactory.attach(address)
        }

        throw new Error('Project not created')
    }

    describe("purchase", function () {
        it("should mint correct tokens when buy different types", async function () {
            let amlokProject = await deploy();

            let value = (3 + 2 + 2);
            await amlokProject.buy([2, 1, 1]);

            expect(await amlokProject.balanceOf(master.address)).to.be.equal(3);
            expect(await token.balanceOf(amlokProject.address)).to.be.equal(value);

            let token1 = await amlokProject.tokenOfOwnerByIndex(master.address, 0);
            expect(await amlokProject.tokenURI(token1)).to.be.equal("ipfs://3.json");

            let token2 = await amlokProject.tokenOfOwnerByIndex(master.address, 1);
            expect(await amlokProject.tokenURI(token2)).to.be.equal("ipfs://2.json");

            let token3 = await amlokProject.tokenOfOwnerByIndex(master.address, 2);
            expect(await amlokProject.tokenURI(token3)).to.be.equal("ipfs://2.json");
        });


        it("should not allow buy more then limit", async function () {
            let amlokProject = await deploy();

            await expect(
                amlokProject.buy([3, 3, 0])
            ).to.be.revertedWith('buy: buy more then limit');
        });

        it("should not allow buy after cancel", async function () {
            let amlokProject = await deploy();
            await time.increase(cancelTimeDelaySecond);
            await expect(
                amlokProject.buy([2, 1, 1])
            ).to.be.revertedWith('buy: allow only for status new');

        })

        it("should not allow buy after get money", async function () {
            let amlokProject = await deploy();
            await amlokProject.buy([2, 1, 1]);

            await amlokProject.withdrawal("");

            await expect(
                amlokProject.buy([0])
            ).to.be.revertedWith('buy: allow only for status new');
        });
    })

    describe('time based', function () {
        it("should change status to canceled after time", async function () {
            let amlokProject = await deploy();

            await time.increase(cancelTimeDelaySecond);

            expect(await amlokProject.getStatus()).to.be.equal(3)
        })

        it("should not allow increase time after canceled", async function () {
            let amlokProject = await deploy();
            await time.increase(cancelTimeDelaySecond);

            await expect(
                amlokProject.setDeadline((await time.latest()) + cancelTimeDelaySecond, "")
            ).to.be.revertedWith('setCancelTime: status should not be canceled');
        })

        it("only owner can change time", async function () {
            let amlokProject = await deploy();

            await expect(
                amlokProject.connect(user).setDeadline((await time.latest()) + cancelTimeDelaySecond, "")
            ).to.be.revertedWith('Ownable: caller is not the owner');
        })
    })

    describe('cancel', function () {
        it("only owner can cancel", async function () {
            let amlokProject = await deploy();

            await expect(
                amlokProject.connect(user).cancel("uri")
            ).to.be.revertedWith('Ownable: caller is not the owner');
        })

        it('should change status to canceled after cancel', async function () {
            let amlokProject = await deploy();

            await amlokProject.cancel("");

            expect(await amlokProject.getStatus()).to.be.equal(3)
        })
    })

    describe("withdrawal", function () {
        it("only owner can do withdrawal", async function () {
            let amlokProject = await deploy();

            await expect(
                amlokProject.connect(user).withdrawal("")
            ).to.be.revertedWith('Ownable: caller is not the owner');
        })

        it("owner can't withdrawal after cancel", async function () {
            let amlokProject = await deploy();
            await time.increase(cancelTimeDelaySecond);

            await expect(
                amlokProject.withdrawal("")
            ).to.be.revertedWith('withdrawal:only for status new or goal reached');
        })

        it("owner should withdrawal and status should changed", async function () {
            let amlokProject = await deploy();
            let value =  (3 + 2 + 2);
            await amlokProject.buy([2, 1, 1]);

            await expect(amlokProject.withdrawal("")).to.changeTokenBalances(
                token,
                [master, amlokProject],
                [value, -value]
            );

            expect(await amlokProject.getStatus()).to.be.equal(2);
        })
    })

    describe("transfer", function () {
        it("owner can transfer nft to user", async function () {
            let amlokProject = await deploy();

            await amlokProject.manualTransfer([2, 1, 1], master.address, "")

            expect(await amlokProject.balanceOf(master.address)).to.be.equal(3);
        })

        it("user can't get money for reFound of this nft", async function () {
            let amlokProject = await deploy();

            await amlokProject.manualTransfer([2, 1, 1], master.address, "")

            await amlokProject.cancel("");
            await amlokProject.reFound();
        })

        it("only owner can do that", async function () {
            let amlokProject = await deploy();

            await expect(
                amlokProject.connect(user).manualTransfer([2, 1, 1], master.address, "")
            ).to.be.revertedWith('Ownable: caller is not the owner');
        })
    })

    describe("reFound", function () {

        it("should reFound only when canceled", async function () {
            let amlokProject = await deploy();
            await amlokProject.buy([2, 1, 1]);

            await expect(
                amlokProject.reFound()
            ).to.be.revertedWith('reFound: only for cancel status');
        })

        it("should reFound all nft", async function () {
            let amlokProject = await deploy();
            let value =  (3 + 2 + 2);
            await amlokProject.buy([2, 1, 1]);
            await amlokProject.cancel("");

            await expect(amlokProject.reFound()).to.changeTokenBalances(
                token,
                [master, amlokProject],
                [value, -value]
            );
            expect(await amlokProject.balanceOf(master.address)).to.be.equal(0)
        })
    })

    describe("distributions", async function () {
        it("user buy 100%, should get 100% distribution", async function () {
            let amlokProject = await deploy();
            await amlokProject.buy([2, 1, 1]);

            await amlokProject.withdrawal("");
            let distributionAmount = 100;

            await amlokProject.createDistribution(distributionAmount, "")

            expect(await amlokProject.calculateDistributionAmount(0, master.address)).to.be.equal(distributionAmount);

            await expect(amlokProject.claimDistributions([0])).to.changeTokenBalances(
                token,
                [master, amlokProject],
                [distributionAmount, -distributionAmount]
            );

            await expect(amlokProject.claimDistributions([0])).to.changeTokenBalances(
                token,
                [master, amlokProject],
                [0, 0]
            );

        })

        it("user buy 50%, should get 50% distribution", async function () {
            let amlokProject = await deploy();
            await amlokProject.buy([2, 1, 1]);
            await amlokProject.connect(user).buy([2, 1, 1]);

            await amlokProject.withdrawal("");
            let distributionAmount = 100;

            await amlokProject.createDistribution(distributionAmount, "")

            expect(await amlokProject.calculateDistributionAmount(0, master.address)).to.be.equal(distributionAmount / 2);

            await expect(amlokProject.claimDistributions([0])).to.changeTokenBalances(
                token,
                [master, amlokProject],
                [distributionAmount / 2, -distributionAmount / 2]
            );

            await expect(amlokProject.claimDistributions([0])).to.changeTokenBalances(
                token,
                [master, amlokProject],
                [0, 0]
            );
        })

    })

    describe("multiple project", function () {
        it("create multiple project with different states", async function () {
            await deploy();
            let amlokProjectUpgradable1 = await deploy();
            await amlokProjectUpgradable1.cancel("");
            await deploy();
            await deploy();
            await deploy();
            let amlokProjectUpgradable = await deploy();
            await amlokProjectUpgradable.buy([2, 1, 1]);
        })
    })
});
