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
			await expect(swift.connect(admin1).setMaxRecipients(ethers.ZeroAddress)).to.be.reverted; // Should fail as zero address checks are in place
		});
	});
});