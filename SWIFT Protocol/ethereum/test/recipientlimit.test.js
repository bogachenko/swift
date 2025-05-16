const {
	expect
} = require("chai");
const {
	ethers
} = require("hardhat");
describe("SWIFT Protocol Recipient Limit Functions", function() {
	let swift;
	let owner, admin1, mod1, user1, user2;
	before(async function() {
		[owner, admin1, mod1, user1, user2] = await ethers.getSigners();
		const SWIFTProtocolFactory = await ethers.getContractFactory("SWIFTProtocol");
		swift = await SWIFTProtocolFactory.deploy({
			value: 1,
		});
		await swift.connect(owner).grantRole(await swift.adminRole(), admin1.address);
		await swift.connect(owner).grantRole(await swift.modRole(), mod1.address);
	});
	describe("setDefaultRecipients", function() {
		it("should reset recipient limit to default for a user", async function() {
			await swift.connect(admin1).setMaxRecipients(user1.address);
			expect(await swift.extendedRecipients(user1.address)).to.be.true;
			await swift.connect(admin1).setDefaultRecipients(user1.address);
			expect(await swift.extendedRecipients(user1.address)).to.be.false;
		});
		it("should emit DefaultRecipientsSet event", async function() {
			await expect(swift.connect(admin1).setDefaultRecipients(user1.address)).to.emit(swift, "DefaultRecipientsSet").withArgs(user1.address, await swift.defaultRecipients());
		});
		it("should reject non-admin/mod calls", async function() {
			await expect(swift.connect(user1).setDefaultRecipients(user2.address)).to.be.revertedWith("Caller is not admin or mod");
		});
		it("should handle multiple users", async function() {
			await swift.connect(admin1).setMaxRecipients(user1.address);
			await swift.connect(admin1).setMaxRecipients(user2.address);
			await swift.connect(mod1).setDefaultRecipients(user1.address);
			await swift.connect(mod1).setDefaultRecipients(user2.address);
			expect(await swift.extendedRecipients(user1.address)).to.be.false;
			expect(await swift.extendedRecipients(user2.address)).to.be.false;
		});
	});
	describe("updateRecipientLimit", function() {
		it("should update current recipient limit within bounds", async function() {
			const defaultLimit = await swift.defaultRecipients();
			const maxLimit = await swift.maxRecipients();
			await swift.connect(admin1).updateRecipientLimit(defaultLimit);
			expect(await swift.currentRecipients()).to.equal(defaultLimit);
			await swift.connect(admin1).updateRecipientLimit(maxLimit);
			expect(await swift.currentRecipients()).to.equal(maxLimit);
			const middleValue = defaultLimit + (maxLimit - defaultLimit) / 2n;
			await swift.connect(admin1).updateRecipientLimit(middleValue);
			expect(await swift.currentRecipients()).to.equal(middleValue);
		});
		it("should emit RecipientLimitUpdated event", async function() {
			const newLimit = 20n;
			await expect(swift.connect(admin1).updateRecipientLimit(newLimit)).to.emit(swift, "RecipientLimitUpdated").withArgs(newLimit);
		});
		it("should reject values below default limit", async function() {
			const defaultLimit = await swift.defaultRecipients();
			await expect(swift.connect(admin1).updateRecipientLimit(defaultLimit - 1n)).to.be.revertedWith("Limit out of bounds");
		});
		it("should reject values above max limit", async function() {
			const maxLimit = await swift.maxRecipients();
			await expect(swift.connect(admin1).updateRecipientLimit(maxLimit + 1n)).to.be.revertedWith("Limit out of bounds");
		});
		it("should reject non-admin/mod calls", async function() {
			await expect(swift.connect(user1).updateRecipientLimit(20n)).to.be.revertedWith("Caller is not admin or mod");
		});
	});
	describe("setMaxRecipients", function() {
		it("should grant extended recipient limit to user", async function() {
			await swift.connect(admin1).setMaxRecipients(user1.address);
			expect(await swift.extendedRecipients(user1.address)).to.be.true;
		});
		it("should emit MaxRecipientsSet event", async function() {
			await expect(swift.connect(admin1).setMaxRecipients(user1.address)).to.emit(swift, "MaxRecipientsSet").withArgs(user1.address, await swift.maxRecipients());
		});
		it("should reject non-admin/mod calls", async function() {
			await expect(swift.connect(user1).setMaxRecipients(user2.address)).to.be.revertedWith("Caller is not admin or mod");
		});
		it("should handle multiple users", async function() {
			await swift.connect(admin1).setMaxRecipients(user1.address);
			await swift.connect(mod1).setMaxRecipients(user2.address);
			expect(await swift.extendedRecipients(user1.address)).to.be.true;
			expect(await swift.extendedRecipients(user2.address)).to.be.true;
		});
		it("should work with zero address", async function() {
			await expect(swift.connect(admin1).setMaxRecipients(ethers.ZeroAddress)).to.be.reverted;
		});
	});
	describe("multiTransfer recipient limits", function() {
		it("should allow transfers up to currentRecipients for standard users", async function() {
			const currentLimit = await swift.currentRecipients();
			const recipients = Array(Number(currentLimit)).fill().map(() => ethers.Wallet.createRandom().address);
			const amount = ethers.parseEther("0.01");
			const amounts = Array(Number(currentLimit)).fill(amount);
			const totalValue = (amount + await swift.taxFee()) * currentLimit;
			await expect(swift.connect(user1).multiTransfer(0,
				ethers.ZeroAddress, recipients, amounts,
				[], false, ethers.randomBytes(32), {
					value: totalValue
				})).to.not.be.reverted;
		});
		it("should reject transfers exceeding currentRecipients for standard users", async function() {
			await ethers.provider.send("evm_increaseTime", [Number(await swift.rateLimitDuration()) + 1]);
			await ethers.provider.send("evm_mine");
			await swift.connect(admin1).setDefaultRecipients(user1.address);
			expect(await swift.extendedRecipients(user1.address)).to.be.false;
			const currentLimit = Number(await swift.currentRecipients());
			const recipients = Array.from({
				length: currentLimit + 1
			}, () => ethers.Wallet.createRandom().address);
			const amountPerRecipient = ethers.parseEther("0.01");
			const taxFee = await swift.taxFee();
			const totalValue = amountPerRecipient * BigInt(currentLimit + 1) + taxFee * BigInt(currentLimit + 1);
			await expect(swift.connect(user1).multiTransfer(0, ethers.ZeroAddress, recipients, recipients.map(() => amountPerRecipient),
				[], false, ethers.randomBytes(32), {
					value: totalValue
				})).to.be.revertedWith("Too many recipients");
		});
		it("should allow transfers up to maxRecipients for users with extended limit", async function() {
			await ethers.provider.send("evm_increaseTime", [Number(await swift.rateLimitDuration()) + 1]);
			await ethers.provider.send("evm_mine");
			await swift.connect(admin1).setMaxRecipients(user1.address);
			expect(await swift.extendedRecipients(user1.address)).to.be.true;
			const maxLimit = Number(await swift.maxRecipients());
			const amountPerRecipient = ethers.parseEther("0.01");
			const taxFee = await swift.taxFee();
			const recipients = Array.from({
				length: maxLimit
			}, () => ethers.Wallet.createRandom().address);
			const amounts = recipients.map(() => amountPerRecipient);
			const totalValue = amountPerRecipient * BigInt(maxLimit) + taxFee * BigInt(maxLimit);
			await expect(swift.connect(user1).multiTransfer(0, ethers.ZeroAddress, recipients, amounts,
				[], false, ethers.randomBytes(32), {
					value: totalValue
				})).to.not.be.reverted;
		});
		it("should reject transfers exceeding maxRecipients even for users with extended limit", async function() {
			await ethers.provider.send("evm_increaseTime", [Number(await swift.rateLimitDuration()) + 1]);
			await ethers.provider.send("evm_mine");
			await swift.connect(admin1).setMaxRecipients(user1.address);
			expect(await swift.extendedRecipients(user1.address)).to.be.true;
			const maxLimit = Number(await swift.maxRecipients());
			const amountPerRecipient = ethers.parseEther("0.01");
			const taxFee = await swift.taxFee();
			const recipients = Array.from({
				length: maxLimit + 1
			}, () => ethers.Wallet.createRandom().address);
			const amounts = recipients.map(() => amountPerRecipient);
			const totalValue = amountPerRecipient * BigInt(maxLimit + 1) + taxFee * BigInt(maxLimit + 1);
			await swift.connect(admin1).setDefaultRecipients(user1.address);
			expect(await swift.extendedRecipients(user1.address)).to.be.false;
			await expect(swift.connect(user1).multiTransfer(0, ethers.ZeroAddress, recipients, amounts,
				[], false, ethers.randomBytes(32), {
					value: totalValue
				})).to.be.revertedWith("Too many recipients");
		});
		it("should apply updated currentRecipients limit", async function() {
			const newLimit = 20n;
			await swift.connect(admin1).updateRecipientLimit(newLimit);
			const recipients = Array.from({
				length: Number(newLimit)
			}, () => ethers.Wallet.createRandom().address);
			const amounts = recipients.map(() => ethers.parseEther("0.01"));
			const totalValue = ethers.parseEther("0.01") * newLimit + (await swift.taxFee()) * newLimit;
			await expect(swift.connect(user2).multiTransfer(0, ethers.ZeroAddress, recipients, amounts,
				[], false, ethers.randomBytes(32), {
					value: totalValue
				})).to.not.be.reverted;
			const tooManyRecipients = Array.from({
				length: Number(newLimit) + 1
			}, () => ethers.Wallet.createRandom().address);
			const tooManyAmounts = tooManyRecipients.map(() => ethers.parseEther("0.01"));
			const taxFee = await swift.taxFee();
			const tooManyValue = ethers.parseEther("0.01") * BigInt(tooManyRecipients.length) + taxFee * BigInt(tooManyRecipients.length);
			await swift.connect(admin1).setDefaultRecipients(user2.address);
			await ethers.provider.send("evm_increaseTime", [Number(await swift.rateLimitDuration()) + 1]);
			await ethers.provider.send("evm_mine");
			await expect(swift.connect(user2).multiTransfer(0, ethers.ZeroAddress, tooManyRecipients, tooManyAmounts,
				[], false, ethers.randomBytes(32), {
					value: tooManyValue
				})).to.be.revertedWith("Too many recipients");
		});
	});
});