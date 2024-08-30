const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");
require("dotenv").config({ path: __dirname + "/.env" });

module.exports = buildModule("DMNGModule", (m) => {
  const tokenName = m.getParameter(
    "tokenName",
    process.env.TOKEN_NAME
  );
  const tokenSymbol = m.getParameter(
    "tokenSymbol",
    process.env.TOKEN_SYMBOL
  );

  const initialSupply = m.getParameter(
    "initialSupply",
    +process.env.INITIAL_SUPPLY
  );
  const softCap = m.getParameter("softCap", +process.env.SOFT_CAP);

  const hardCap = m.getParameter("hardCap", +process.env.HARD_CAP);

  const initialOwner = m.getParameter(
    "initialOwner",
    process.env.INITIAL_OWNER
  );
  const ntzcContract = m.getParameter(
    "ntzcContract",
    process.env.NTZC_CONTRACT
  );

  const customDecimals = m.getParameter(
    "customDecimals",
    +process.env.CUSTOM_DECIMALS
  );
  const campaignEndTime = m.getParameter(
    "campaignEndTime",
    +process.env.CAMPAIGN_END_TIME
  );

  const admin = m.getParameter("admin", process.env.ADMIN);

  const dmng = m.contract("NCIContract", [
    tokenName,
    tokenSymbol,
    initialSupply,
    softCap,
    hardCap,
    campaignEndTime,
    customDecimals,
    ntzcContract,
    initialOwner,
    admin,
  ]);

  return { dmng };
});
