// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./IERC20Extended.sol";

contract DMNGToken is ERC20, Ownable {
    using SafeERC20 for IERC20Extended;

    uint8 private customDecimals;
    uint256 public baseTokenPrice;
    uint256 public currentSupply;
    uint256 public softCap;
    uint256 public hardCap;
    uint256 public investorPool;
    uint256 public profitPool;
    uint256 public campaignStartTime;
    uint256 public campaignEndTime;
    bool public campaignCompleted;

    IERC20Extended public usdtContract;

    // mappings
    mapping(address => bool) public admin;
    mapping(address => uint256) public balances;

    // events
    event TokensPurchased(
        address indexed investor,
        uint256 tokenAmount,
        uint256 dmngToken,
        uint256 baseTokenPrice,
        uint256 blockTimestamp
    );
    event ProfitAdded(
        address indexed ownerAdminAddress,
        uint256 amount,
        uint256 blockTimestamp
    );
    event BaseTokenPriceUpdated(uint256 newPrice);
    event WithdrawnInvestor(
        address indexed investor,
        uint256 dmngToken,
        uint256 tokenAmount,
        uint256 blockTimestamp
    );
    event WithdrawAdminOwner(
        address indexed ownerAdminAddress,
        uint256 tokenAmount,
        uint256 blockTimestamp
    );
    event UpdateAdmin(
        address indexed adminAddress,
        bool value
    );

    constructor(
        uint256 _initialSupply,
        uint256 _softCap,
        uint256 _hardCap,
        uint256 _campaignEndTime,
        uint8 _customDecimals,
        address _usdtContract,
        address _initialOwner,
        address _admin
    ) Ownable(_initialOwner) ERC20("DMNG Token", "DMNG") {
        require(block.timestamp < _campaignEndTime, "Campaign end time must be in the future");
        _mint(address(this), _initialSupply * (10**_customDecimals));
        currentSupply = _initialSupply * (10**_customDecimals);
        softCap = _softCap * (10**_customDecimals);
        hardCap = _hardCap * (10**_customDecimals);
        campaignCompleted = false;
        usdtContract = IERC20Extended(_usdtContract);
        baseTokenPrice = 5 * (10**IERC20Extended(_usdtContract).decimals());
        customDecimals = _customDecimals;
        campaignStartTime = block.timestamp;
        campaignEndTime =  _campaignEndTime;
        admin[_admin];
    }

    modifier onlyDuringCampaign() {
        require(
            block.timestamp >= campaignStartTime &&
            block.timestamp <= campaignEndTime,
            "Campaign is not active"
        );
        _;
    }

    modifier campaignIncomplete() {
        require(!campaignCompleted, "Campaign has been completed");
        _;
    }

    modifier campaignCompletedOnly() {
        require(campaignCompleted, "Campaign is not completed");
        _;
    }

   modifier onlyAdminOrOwner() {
        require( admin[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }
    function buyTokens(uint256 _tokenValue) 
        external 
        // onlyDuringCampaign 
        // campaignIncomplete 
    {
        require(_tokenValue > 0, "Amount must be greater than zero");

        // Checking allowance and balance of investor
        require(
            usdtContract.allowance(msg.sender, address(this)) >= _tokenValue &&
            usdtContract.balanceOf(msg.sender) >= _tokenValue,
            "Insufficient allowance or balance"
        );

        uint256 tokensToPurchase = (_tokenValue / baseTokenPrice)* 10 ** customDecimals;

        // Checking contract has enough DMNG tokens
        require(
            balanceOf(address(this)) >= tokensToPurchase,
            "Not enough tokens available"
        );

        // Transfer USDT from investor to contract
        usdtContract.safeTransferFrom(msg.sender, address(this), _tokenValue);
        investorPool += _tokenValue;

        balances[msg.sender] += tokensToPurchase;
        currentSupply -= tokensToPurchase;

        // Transfer DMNG tokens to investor wallet
        _transfer(address(this), msg.sender, tokensToPurchase);

        // Check if soft cap is reached
        uint256 cap = totalSupply() - softCap;
        if (currentSupply == cap) {
            campaignCompleted = true;
        }

        emit TokensPurchased(
            msg.sender,
            _tokenValue,
            tokensToPurchase,
            baseTokenPrice,
            block.timestamp
        );
    }

    function sellTokens(uint256 _tokenValue) 
        external 
        campaignCompletedOnly 
    {
        require(
            _tokenValue > 0 && balances[msg.sender] >= _tokenValue,
            "Insufficient balance"
        );

        uint256 tokens = (_tokenValue * baseTokenPrice) / 10**usdtContract.decimals();
        require(profitPool >= tokens, "Pool needs to be balanced to withdraw");

        balances[msg.sender] -= _tokenValue;

        // Transfer USDT back to the investor
        usdtContract.safeTransfer(msg.sender, tokens);

        profitPool -= tokens;

        emit WithdrawnInvestor(
            msg.sender,
            _tokenValue,
            tokens,
            block.timestamp
        );
    }

    function withdrawAdminOwner(uint256 _tokenValue) 
        external 
        campaignCompletedOnly 
    {
        require(investorPool >= _tokenValue, "Insufficient liquidity in pool");

        usdtContract.safeTransfer(msg.sender, _tokenValue);
        investorPool -= _tokenValue;

        emit WithdrawAdminOwner(msg.sender, _tokenValue, block.timestamp);
    }

    function addProfit(uint256 _profitAmount) 
        external 
        onlyOwner 
        campaignCompletedOnly 
    {
        require(_profitAmount > 0, "Amount must be greater than zero");

        // Transfer USDT from admin to contract
        usdtContract.safeTransferFrom(msg.sender, address(this), _profitAmount);
        profitPool += _profitAmount;

        uint256 newTokenValue = calculateNewTokenValue(_profitAmount);
        baseTokenPrice =  baseTokenPrice + newTokenValue * (10**usdtContract.decimals());

        emit BaseTokenPriceUpdated(baseTokenPrice);
        emit ProfitAdded(msg.sender, _profitAmount, block.timestamp);
    }

    function calculateNewTokenValue(uint256 _profitAmount) 
        public 
        view 
        returns (uint256) 
    {
        return _profitAmount / currentSupply;
    }

    function decimals() 
        public 
        view 
        virtual 
        override 
        returns (uint8) 
    {
        return customDecimals;
    }

      function updateSubAdmin(address _admin, bool _value)
        external
        onlyAdminOrOwner
    {
        require( _admin!= address(0), "admin address cannot be zero address");
        admin[_admin] = _value;
        emit UpdateAdmin(_admin, _value);
    }
}
